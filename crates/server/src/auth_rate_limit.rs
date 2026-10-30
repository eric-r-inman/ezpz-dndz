//! Per-IP rate limit on `/api/auth/login` and
//! `/api/auth/register`.
//!
//! The auth endpoints are the only routes that gate access to
//! per-user state, so brute-force protection there matters more
//! than anywhere else.  Without a limiter, a script can hammer
//! login with millions of attempts and burn CPU on Argon2id
//! verification.  With it, repeated failures from one client get
//! `429 Too Many Requests` and the GM's box stays responsive.
//!
//! This is a deliberately small implementation: a fixed-window
//! token bucket keyed by client IP, held in process memory.
//! Resets every [`WINDOW`] seconds; the cap is
//! [`MAX_ATTEMPTS_PER_WINDOW`].  For 1–20-user homelab
//! deployments that is plenty; switch to `tower-governor` or a
//! distributed limiter if you ever federate across hosts.
//!
//! The bucket key comes from `X-Forwarded-For` only when the
//! operator says a reverse proxy writes it.  See
//! [`AuthRateLimiter::client_ip`].

use std::{
  collections::HashMap,
  net::IpAddr,
  sync::Arc,
  time::{Duration, Instant},
};

use axum::{
  extract::{Request, State},
  http::{HeaderMap, StatusCode},
  middleware::Next,
  response::{IntoResponse, Response},
  Json,
};
use tokio::sync::Mutex;
use tracing::warn;

/// The bucket key for a request whose client the limiter cannot
/// name.  One shared bucket is better than no limit at all.
const DIRECT_FALLBACK_IP: IpAddr =
  IpAddr::V4(std::net::Ipv4Addr::new(0, 0, 0, 0));

/// Length of the rate-limit window.  Restarting the bucket every
/// minute is short enough to recover from honest typos quickly
/// and long enough that an automated brute-forcer can't get more
/// than [`MAX_ATTEMPTS_PER_WINDOW`] tries per minute.
pub const WINDOW: Duration = Duration::from_secs(60);

/// Maximum auth attempts per IP per [`WINDOW`].  Tuned for the
/// homelab case: a human typing their password into the wrong
/// field a few times stays well under, a botnet hits the limit
/// on the third try and gets bounced.
pub const MAX_ATTEMPTS_PER_WINDOW: u32 = 10;

/// Above this number of tracked IPs the limiter sweeps expired
/// buckets to keep memory bounded.  Set well above
/// [`MAX_ATTEMPTS_PER_WINDOW`]'s legitimate working set; the
/// sweep is O(n) but cheap because the map only holds a few
/// hundred entries in practice.
const SWEEP_THRESHOLD: usize = 1024;

#[derive(Clone)]
pub struct AuthRateLimiter {
  inner: Arc<Mutex<HashMap<IpAddr, BucketState>>>,
  trust_forwarded_for: bool,
}

#[derive(Debug)]
struct BucketState {
  attempts: u32,
  window_start: Instant,
}

impl AuthRateLimiter {
  /// `trust_forwarded_for` says a reverse proxy writes
  /// `X-Forwarded-For` on every request.
  pub fn new(trust_forwarded_for: bool) -> Self {
    Self {
      inner: Arc::new(Mutex::new(HashMap::new())),
      trust_forwarded_for,
    }
  }

  /// The client a request's attempts count against.
  ///
  /// Behind a trusted proxy it is the last `X-Forwarded-For` entry.
  /// The proxy wrote that one.  Any earlier entry came from the
  /// client and could be forged.  Without a trusted proxy the header
  /// is ignored.  Every client then shares one bucket.  The
  /// foundation's listener does not hand the peer address on.
  fn client_ip(&self, headers: &HeaderMap) -> IpAddr {
    if self.trust_forwarded_for {
      headers
        .get("x-forwarded-for")
        .and_then(|value| {
          value
            .to_str()
            .inspect_err(|error| {
              warn!(%error, "X-Forwarded-For is not text; using the shared bucket");
            })
            .ok()
        })
        .and_then(|text| text.rsplit(',').next())
        .and_then(|last| {
          last
            .trim()
            .parse::<IpAddr>()
            .inspect_err(|error| {
              warn!(%error, entry = last, "X-Forwarded-For entry is not an address; using the shared bucket");
            })
            .ok()
        })
        .unwrap_or(DIRECT_FALLBACK_IP)
    } else {
      DIRECT_FALLBACK_IP
    }
  }

  /// Record one attempt from `ip` and decide whether the request
  /// is allowed.  When the window rolls over the bucket resets
  /// to a single attempt and `Ok(())` is returned regardless of
  /// the prior count.
  ///
  /// O(1) average; opportunistically sweeps expired entries when
  /// the map grows past [`SWEEP_THRESHOLD`] so a memory leak
  /// from random scanners can't grow without bound.
  pub async fn record_and_check(&self, ip: IpAddr) -> Result<(), TooMany> {
    let mut map = self.inner.lock().await;
    let now = Instant::now();

    if map.len() > SWEEP_THRESHOLD {
      map.retain(|_, state| now.duration_since(state.window_start) < WINDOW);
    }

    let entry = map.entry(ip).or_insert(BucketState {
      attempts: 0,
      window_start: now,
    });

    if now.duration_since(entry.window_start) >= WINDOW {
      entry.attempts = 1;
      entry.window_start = now;
      return Ok(());
    }

    entry.attempts = entry.attempts.saturating_add(1);
    if entry.attempts > MAX_ATTEMPTS_PER_WINDOW {
      let retry_after = WINDOW
        .saturating_sub(now.duration_since(entry.window_start))
        .as_secs();
      Err(TooMany {
        retry_after_secs: retry_after.max(1),
      })
    } else {
      Ok(())
    }
  }
}

#[derive(Debug)]
pub struct TooMany {
  /// Number of seconds the client should wait before retrying.
  /// Surfaced back to the caller in the `Retry-After` header per
  /// RFC 9110, so well-behaved clients (and the friendly login
  /// form) can show a countdown rather than retry-spamming.
  pub retry_after_secs: u64,
}

/// Axum middleware applied to the login + register routes.
/// Returns `429 Too Many Requests` with a `Retry-After` header
/// when the per-IP bucket overflows.
pub async fn middleware(
  State(limiter): State<AuthRateLimiter>,
  headers: HeaderMap,
  request: Request,
  next: Next,
) -> Response {
  let ip = limiter.client_ip(&headers);
  match limiter.record_and_check(ip).await {
    Ok(()) => next.run(request).await,
    Err(too_many) => (
      StatusCode::TOO_MANY_REQUESTS,
      [(
        axum::http::header::RETRY_AFTER,
        too_many.retry_after_secs.to_string(),
      )],
      Json(serde_json::json!({
        "error":
          "Too many authentication attempts.  Please wait and try \
           again.",
        "retry_after_secs": too_many.retry_after_secs,
      })),
    )
      .into_response(),
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn forwarded(value: &str) -> HeaderMap {
    HeaderMap::from_iter([(
      axum::http::HeaderName::from_static("x-forwarded-for"),
      value.parse().unwrap(),
    )])
  }

  #[test]
  fn an_untrusted_header_is_ignored() {
    let limiter = AuthRateLimiter::new(false);
    assert_eq!(
      limiter.client_ip(&forwarded("203.0.113.7")),
      DIRECT_FALLBACK_IP
    );
  }

  #[test]
  fn a_trusted_header_counts_the_entry_the_proxy_wrote() {
    let limiter = AuthRateLimiter::new(true);
    assert_eq!(
      limiter.client_ip(&forwarded("203.0.113.7, 198.51.100.2")),
      "198.51.100.2".parse::<IpAddr>().unwrap()
    );
  }

  #[test]
  fn a_trusted_but_unreadable_header_falls_back_to_the_shared_bucket() {
    let limiter = AuthRateLimiter::new(true);
    assert_eq!(
      limiter.client_ip(&forwarded("not an address")),
      DIRECT_FALLBACK_IP
    );
  }
}
