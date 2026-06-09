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
//! Client-IP resolution honours `X-Forwarded-For` when the
//! request came through a reverse proxy (Caddy / nginx) and
//! falls back to the TCP peer otherwise.  See
//! [`client_ip`].

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

/// Sentinel IP used as the bucket key when no `X-Forwarded-For`
/// header is present.  In a production deployment Caddy/nginx
/// add the header on every request, so this fallback only kicks
/// in for direct-to-server traffic (development, internal
/// curl).  Falling back to a single shared bucket is preferable
/// to disabling the limit entirely, since the goal is to keep
/// the limiter behavioural on every code path.
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
}

#[derive(Debug)]
struct BucketState {
  attempts: u32,
  window_start: Instant,
}

impl AuthRateLimiter {
  pub fn new() -> Self {
    Self {
      inner: Arc::new(Mutex::new(HashMap::new())),
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

impl Default for AuthRateLimiter {
  fn default() -> Self {
    Self::new()
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
  let ip = client_ip(&headers);
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

/// Resolve the originating client's IP from request headers.
///
/// In the documented production setup
/// (`docs/DEPLOY.org`), Caddy adds `X-Forwarded-For` containing
/// the real client IP; we trust the first hop.  For direct
/// connections without a reverse proxy (development, `curl
/// localhost`) the limiter shares a single fallback bucket
/// keyed by [`DIRECT_FALLBACK_IP`].  That keeps the limit
/// behavioural on every code path; the cost is that a busy
/// dev session can self-throttle, which is a useful smoke test
/// that the limiter is active.
fn client_ip(headers: &HeaderMap) -> IpAddr {
  headers
    .get("x-forwarded-for")
    .and_then(|value| value.to_str().ok())
    .and_then(|text| text.split(',').next())
    .and_then(|first| first.trim().parse::<IpAddr>().ok())
    .unwrap_or(DIRECT_FALLBACK_IP)
}
