//! Integration tests for the relational-storage migration: the
//! one-shot users + dice-history JSON import, the byte-level dice
//! round-trip against the Elm wire shape, the per-user cap eviction
//! now implemented in SQL (phase 1), and the five normalized
//! per-user preset stores — exact wire round-trips, tri-state
//! null/empty semantics, and the legacy-shape boot import (phase 2).

// File-scoped overrides: `allow-expect-in-tests` covers items inside
// `#[test]` / `#[cfg(test)]`, but the helpers below sit at crate
// scope.  Test failure via panic is the desired signal here.
#![allow(clippy::expect_used, clippy::unwrap_used)]

use aide::axum::ApiRouter;
use argon2::{
  password_hash::{rand_core::OsRng, PasswordHasher, SaltString},
  Argon2,
};
use axum::{
  body::Body,
  http::{Request, StatusCode},
  middleware, Router,
};
use ezpz_dndz_lib::db::{default_sqlite_url, Db};
use ezpz_dndz_server::{
  compendium, config::RuntimePaths, dice, encounters, per_user_store, users,
  web_base::AppState,
};
use rust_template_foundation::server::runner::{
  BaseServerState, ServerRunConfig,
};
use rust_template_foundation::Server;
use serde_json::{json, Value};
use tempfile::TempDir;
use tokio_listener::ListenerAddress;
use tower::ServiceExt;

/// Build an `AppState` over an EXISTING data dir so tests can drop
/// legacy JSON fixtures in place before the boot-time import runs.
async fn app_state_for_dir(dir: &TempDir) -> AppState {
  let paths = RuntimePaths::from_data_dir(dir.path());
  let run_config = ServerRunConfig {
    app_name: "ezpz-dndz".to_string(),
    listen_address: "127.0.0.1:0"
      .parse::<ListenerAddress>()
      .expect("listen address"),
    base_url: "http://localhost:0".to_string(),
    oidc: None,
  };
  let base = BaseServerState::init(&run_config)
    .await
    .expect("base server state");
  let db = Db::connect(&default_sqlite_url(dir.path()))
    .await
    .expect("test database");
  AppState::assemble(base, db, &paths, None)
    .await
    .expect("app state assemble")
}

fn build_test_router(state: AppState) -> Router {
  let run_config = ServerRunConfig {
    app_name: "ezpz-dndz".to_string(),
    listen_address: "127.0.0.1:0"
      .parse::<ListenerAddress>()
      .expect("listen address"),
    base_url: "http://localhost:0".to_string(),
    oidc: None,
  };

  let auth_state = state.clone();
  let protected: ApiRouter<AppState> = ApiRouter::new()
    .merge(dice::router())
    .merge(compendium::router())
    .merge(encounters::router())
    .merge(per_user_store::routers(&state))
    .layer(middleware::from_fn_with_state(auth_state, users::require_auth));

  let users_state = state.clone();
  Server::new(state.base.clone(), run_config)
    .with_state(move |_base| state)
    .merge(users::router(users_state))
    .merge(protected)
    .into_test_router()
}

fn extract_session_cookie(
  response: &axum::response::Response,
) -> Option<String> {
  response
    .headers()
    .get_all(axum::http::header::SET_COOKIE)
    .iter()
    .filter_map(|v| v.to_str().ok())
    .find_map(|raw| {
      raw
        .split(';')
        .next()
        .and_then(|first| first.trim().strip_prefix("id=").map(str::to_string))
        .map(|val| format!("id={val}"))
    })
}

async fn read_body(response: axum::response::Response) -> String {
  let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
    .await
    .expect("read body");
  String::from_utf8(bytes.to_vec()).expect("utf-8 body")
}

async fn register_and_get_cookie(app: &Router) -> String {
  let response = app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/auth/register")
        .header("content-type", "application/json")
        .body(Body::from(
          r#"{"email":"alice@example.com","password":"hunter2hunter","display_name":"Alice"}"#,
        ))
        .unwrap(),
    )
    .await
    .expect("register request");
  assert_eq!(response.status(), StatusCode::CREATED);
  extract_session_cookie(&response).expect("session cookie on register")
}

async fn post_roll(app: &Router, cookie: &str, payload: &Value) -> StatusCode {
  app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/dice/history")
        .header("content-type", "application/json")
        .header("cookie", cookie)
        .body(Body::from(payload.to_string()))
        .unwrap(),
    )
    .await
    .unwrap()
    .status()
}

async fn get_history(app: &Router, cookie: &str) -> Vec<Value> {
  let response = app
    .clone()
    .oneshot(
      Request::builder()
        .uri("/api/dice/history")
        .header("cookie", cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(response.status(), StatusCode::OK);
  serde_json::from_str(&read_body(response).await).expect("history JSON")
}

/// A full-shape roll exactly as `Dice.encodeRoll` emits it (field
/// set copied from frontend/src/Dice.elm).
fn elm_shaped_roll(total: i64, timestamp: i64) -> Value {
  json!({
    "kind": "standard",
    "formula": "3d6 Radiant",
    "total": total,
    "timestamp": timestamp,
    "expression": {
      "dice": [ { "count": 3, "faces": 6, "sign": "positive" } ],
      "constant": 0,
      "damageType": "Radiant"
    },
    "groups": [
      {
        "dice": { "count": 3, "faces": 6, "sign": "positive" },
        "rolled": [
          { "face": 1, "kept": true },
          { "face": 3, "kept": true },
          { "face": 6, "kept": true }
        ],
        "subtotal": 10
      }
    ],
    "source": { "feature": "Damage", "target": "Goblin" }
  })
}

// ── dice wire round-trip ────────────────────────────────────────────────────

#[tokio::test]
async fn test_dice_elm_shaped_roll_round_trips_exactly() {
  let dir = TempDir::new().expect("tempdir");
  let state = app_state_for_dir(&dir).await;
  let app = build_test_router(state);
  let cookie = register_and_get_cookie(&app).await;

  let roll = elm_shaped_roll(11, 1714502400000);
  assert_eq!(post_roll(&app, &cookie, &roll).await, StatusCode::OK);

  let history = get_history(&app, &cookie).await;
  assert_eq!(history.len(), 1);
  assert_eq!(
    history[0], roll,
    "GET must return exactly the JSON that was POSTed"
  );
}

#[tokio::test]
async fn test_dice_advantage_roll_with_nulls_round_trips_exactly() {
  // Advantage roll: dropped die (kept: false), null damageType and
  // null target — the fields the Elm decoder requires to be present
  // as literal null rather than absent.
  let dir = TempDir::new().expect("tempdir");
  let state = app_state_for_dir(&dir).await;
  let app = build_test_router(state);
  let cookie = register_and_get_cookie(&app).await;

  let roll = json!({
    "kind": "advantage",
    "formula": "1d20+5",
    "total": 23,
    "timestamp": 1714502500000i64,
    "expression": {
      "dice": [ { "count": 1, "faces": 20, "sign": "positive" } ],
      "constant": 5,
      "damageType": null
    },
    "groups": [
      {
        "dice": { "count": 2, "faces": 20, "sign": "positive" },
        "rolled": [
          { "face": 18, "kept": true },
          { "face": 4, "kept": false }
        ],
        "subtotal": 18
      }
    ],
    "source": { "feature": "Attack", "target": null }
  });
  assert_eq!(post_roll(&app, &cookie, &roll).await, StatusCode::OK);

  let history = get_history(&app, &cookie).await;
  assert_eq!(history.len(), 1);
  assert_eq!(history[0], roll);
}

#[tokio::test]
async fn test_dice_cap_evicts_oldest_beyond_max_entries() {
  let dir = TempDir::new().expect("tempdir");
  let state = app_state_for_dir(&dir).await;
  let app = build_test_router(state);
  let cookie = register_and_get_cookie(&app).await;

  let n = dice::MAX_ENTRIES + 5;
  for i in 0..n {
    let mut roll = elm_shaped_roll(i as i64, 1714502400000 + i as i64);
    // A scalar extra field, like the legacy opaque contract allowed;
    // also serves as the marker for eviction-order assertions.
    roll["id"] = json!(i);
    assert_eq!(post_roll(&app, &cookie, &roll).await, StatusCode::OK);
  }

  let history = get_history(&app, &cookie).await;
  assert_eq!(
    history.len(),
    dice::MAX_ENTRIES,
    "history must be capped at MAX_ENTRIES"
  );
  let ids: Vec<i64> = history
    .iter()
    .map(|e| e["id"].as_i64().expect("id extra"))
    .collect();
  let expected: Vec<i64> = (5..n as i64).rev().collect();
  assert_eq!(
    ids, expected,
    "newest rolls first; the oldest five must have been evicted"
  );
}

#[tokio::test]
async fn test_dice_clear_empties_the_history() {
  let dir = TempDir::new().expect("tempdir");
  let state = app_state_for_dir(&dir).await;
  let app = build_test_router(state);
  let cookie = register_and_get_cookie(&app).await;

  let roll = elm_shaped_roll(9, 1714502400000);
  assert_eq!(post_roll(&app, &cookie, &roll).await, StatusCode::OK);

  let delete = app
    .clone()
    .oneshot(
      Request::builder()
        .method("DELETE")
        .uri("/api/dice/history")
        .header("cookie", &cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(delete.status(), StatusCode::NO_CONTENT);

  assert_eq!(get_history(&app, &cookie).await, Vec::<Value>::new());
}

// ── legacy JSON import ──────────────────────────────────────────────────────

fn argon2id_hash(password: &str) -> String {
  let salt = SaltString::generate(&mut OsRng);
  Argon2::default()
    .hash_password(password.as_bytes(), &salt)
    .expect("hash fixture password")
    .to_string()
}

/// Write the legacy users.json + dice-history.json fixtures in the
/// exact shapes the JsonFileStore-era server persisted.
fn write_legacy_fixtures(dir: &TempDir, user_id: &str) -> (Value, Value) {
  let users = json!([
    {
      "id": user_id,
      "email": "legacy@example.com",
      "password_hash": argon2id_hash("hunter2hunter"),
      "display_name": "Legacy",
      "created_at": 1700000000u64
    }
  ]);
  // Newest first, matching the on-disk order the old store kept.
  let newest = elm_shaped_roll(15, 1714502500000);
  let oldest = elm_shaped_roll(7, 1714502400000);
  let dice_history = json!({ user_id: [newest, oldest] });

  std::fs::write(
    dir.path().join("users.json"),
    serde_json::to_vec_pretty(&users).expect("encode users fixture"),
  )
  .expect("write users.json");
  std::fs::write(
    dir.path().join("dice-history.json"),
    serde_json::to_vec_pretty(&dice_history).expect("encode dice fixture"),
  )
  .expect("write dice-history.json");
  (users, dice_history)
}

#[tokio::test]
async fn test_json_import_users_and_dice_round_trip() {
  let dir = TempDir::new().expect("tempdir");
  let user_id = "07d6a89a-9bb3-4b1b-87ef-6a12d6ce157c";
  let (_users, dice_history) = write_legacy_fixtures(&dir, user_id);

  let state = app_state_for_dir(&dir).await;
  let app = build_test_router(state);

  // The imported account can log in with the original password.
  let login = app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/auth/login")
        .header("content-type", "application/json")
        .body(Body::from(
          r#"{"email":"legacy@example.com","password":"hunter2hunter"}"#,
        ))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(login.status(), StatusCode::OK);
  let cookie = extract_session_cookie(&login).expect("login cookie");
  let login_body: Value =
    serde_json::from_str(&read_body(login).await).expect("login body");
  assert_eq!(login_body["id"], user_id);
  assert_eq!(login_body["display_name"], "Legacy");
  assert_eq!(login_body["created_at"], 1700000000u64);

  // The imported dice history reads back identically, newest first.
  let history = get_history(&app, &cookie).await;
  assert_eq!(
    Value::Array(history),
    dice_history[user_id],
    "imported dice history must match the legacy file exactly"
  );

  // The legacy files are left in place as the rollback copy.
  assert!(dir.path().join("users.json").exists());
  assert!(dir.path().join("dice-history.json").exists());
}

#[tokio::test]
async fn test_json_import_runs_only_once() {
  let dir = TempDir::new().expect("tempdir");
  let user_id = "17d6a89a-9bb3-4b1b-87ef-6a12d6ce157c";
  write_legacy_fixtures(&dir, user_id);

  // First boot imports; second boot must see the marker and leave
  // the database alone (no duplicate users or rolls).
  let _first = app_state_for_dir(&dir).await;
  let state = app_state_for_dir(&dir).await;
  let app = build_test_router(state);

  let login = app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/auth/login")
        .header("content-type", "application/json")
        .body(Body::from(
          r#"{"email":"legacy@example.com","password":"hunter2hunter"}"#,
        ))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(login.status(), StatusCode::OK);
  let cookie = extract_session_cookie(&login).expect("login cookie");
  assert_eq!(
    get_history(&app, &cookie).await.len(),
    2,
    "re-boot must not duplicate the imported rolls"
  );
}

#[tokio::test]
async fn test_json_import_preserves_duplicate_email_rejection() {
  let dir = TempDir::new().expect("tempdir");
  let user_id = "27d6a89a-9bb3-4b1b-87ef-6a12d6ce157c";
  write_legacy_fixtures(&dir, user_id);

  let state = app_state_for_dir(&dir).await;
  let app = build_test_router(state);

  // Registering the imported address must hit the UNIQUE constraint
  // and surface as the same 409 the JSON store produced.
  let conflict = app
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/auth/register")
        .header("content-type", "application/json")
        .body(Body::from(
          r#"{"email":"legacy@example.com","password":"hunter2hunter","display_name":"Impostor"}"#,
        ))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(conflict.status(), StatusCode::CONFLICT);
}

// ── per-user preset stores (phase 2) ────────────────────────────────────────
//
// The five preset stores are normalized into real tables (migration
// 0002) behind codecs that mirror the Elm *.Wire modules.  The tests
// below pin, per feature:
//
// (a) a realistic FULL payload in the exact shape the Elm encoder
//     emits round-trips to byte-equivalent JSON (Value equality);
// (b) tri-state semantics: a persisted-but-EMPTY collection reads
//     back as that empty collection, not null (GET-null before the
//     first PUT and per-user isolation are pinned by the sibling
//     integration_test.rs suite);
// (c) the one-shot boot import decodes LEGACY wire shapes and serves
//     them back in the canonical modern encoding, skipping (not
//     aborting on) undecodable or unattributable entries.

async fn put_json(
  app: &Router,
  cookie: &str,
  path: &str,
  payload: &Value,
) -> StatusCode {
  app
    .clone()
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri(path)
        .header("content-type", "application/json")
        .header("cookie", cookie)
        .body(Body::from(payload.to_string()))
        .unwrap(),
    )
    .await
    .unwrap()
    .status()
}

async fn get_json(app: &Router, cookie: &str, path: &str) -> Value {
  let response = app
    .clone()
    .oneshot(
      Request::builder()
        .uri(path)
        .header("cookie", cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(response.status(), StatusCode::OK, "GET {path}");
  serde_json::from_str(&read_body(response).await).expect("GET body JSON")
}

/// PUT `payload` and assert GET returns exactly the same JSON value.
async fn assert_exact_roundtrip(path: &str, payload: Value) {
  let dir = TempDir::new().expect("tempdir");
  let state = app_state_for_dir(&dir).await;
  let app = build_test_router(state);
  let cookie = register_and_get_cookie(&app).await;

  assert_eq!(put_json(&app, &cookie, path, &payload).await, StatusCode::OK);
  assert_eq!(
    get_json(&app, &cookie, path).await,
    payload,
    "GET {path} must return exactly the canonical JSON that was PUT"
  );
}

fn full_lore_groups() -> Value {
  json!([
    {
      "id": "grp-goblins",
      "name": "Goblin warband",
      "weight": 5,
      "source": "user",
      "members": [
        { "name": "Goblin Boss", "role": "leader", "count_min": 1, "count_max": 1 },
        { "name": "Goblin", "role": "member", "count_min": 2, "count_max": 6 },
        { "name": "Worg", "role": "pet", "count_min": 0, "count_max": 2 }
      ],
      "description": "A raiding party with a bossy leader."
    },
    {
      "id": "grp-cult",
      "name": "Cult of the Dragon",
      "weight": 3,
      "source": "bundled",
      "members": [
        { "name": "Cultist", "role": "minion", "count_min": 4, "count_max": 8 }
      ],
      "description": ""
    }
  ])
}

fn full_condition_presets() -> Value {
  json!({
    "Hold (DC 15 WIS)": {
      "conditionName": "Paralyzed",
      "customName": "",
      "note": "Hold Person",
      "durationKind": "untilTurn",
      "untilPhase": "atEnd",
      "countdownTurnsText": "3",
      "countdownTurns": 3,
      "countdownPhase": "atBegin",
      "saveToEnd": {
        "ability": "wis",
        "dcText": "15",
        "dc": 15,
        "bonusText": "+1",
        "bonus": 1,
        "autoRoll": "atEnd"
      },
      "category": ""
    },
    "Burning": {
      "conditionName": "Custom",
      "customName": "Burning",
      "note": "1d6 fire at turn start",
      "durationKind": "countdown",
      "untilPhase": "atBegin",
      "countdownTurnsText": "2",
      "countdownTurns": 2,
      "countdownPhase": "atEnd",
      "saveToEnd": null,
      "category": "srd"
    }
  })
}

/// Bundled-style Save Chain map exercising every HP-effect kind, a
/// multi-effect outcome, and all `save_to_end` enum variants.
fn full_save_chains() -> Value {
  json!({
    "Fireball": {
      "name": "Fireball",
      "save_ability": "dex",
      "save_dc": null,
      "on_fail": {
        "hp": { "kind": "damage", "amount": "8d6" },
        "effects": []
      },
      "on_success": {
        "hp": { "kind": "half_fail" },
        "effects": []
      }
    },
    "Hold Person": {
      "name": "Hold Person",
      "save_ability": "wis",
      "save_dc": 15,
      "on_fail": {
        "hp": { "kind": "none" },
        "effects": [
          { "name": "Paralyzed", "note": "Hold Person", "save_to_end": "at_end" },
          { "name": "Marked", "note": "", "save_to_end": null }
        ]
      },
      "on_success": {
        "hp": { "kind": "none" },
        "effects": []
      }
    },
    "Healing Word": {
      "name": "Healing Word",
      "save_ability": "cha",
      "save_dc": 12,
      "on_fail": {
        "hp": { "kind": "none" },
        "effects": [
          { "name": "Inspired", "note": "manual save", "save_to_end": "manual" },
          { "name": "Watched", "note": "", "save_to_end": "at_begin" }
        ]
      },
      "on_success": {
        "hp": { "kind": "heal", "amount": "1d4+2" },
        "effects": []
      }
    }
  })
}

/// A treasure table hitting every dict category, explicit coin
/// nulls, hoard sub-roll specs, all seven optional fields, and an
/// empty bracket list (a key the GM emptied but kept).
fn full_treasure_table() -> Value {
  json!({
    "individualBrackets": {
      "1to4": [
        {
          "weight": 30,
          "copper": { "count": 5, "faces": 6, "mult": 1 },
          "silver": null,
          "electrum": null,
          "gold": null,
          "platinum": null
        },
        {
          "weight": 10,
          "copper": null,
          "silver": { "count": 4, "faces": 6, "mult": 1 },
          "electrum": null,
          "gold": { "count": 1, "faces": 4, "mult": 1 },
          "platinum": null
        }
      ],
      "17plus": []
    },
    "hoardBrackets": {
      "5to10": [
        {
          "weight": 4,
          "copper": { "count": 2, "faces": 6, "mult": 100 },
          "silver": null,
          "electrum": { "count": 1, "faces": 6, "mult": 10 },
          "gold": { "count": 6, "faces": 6, "mult": 10 },
          "platinum": null,
          "gems": { "count": 2, "faces": 4, "tier": "50gp" },
          "art": null,
          "magic": { "count": 1, "faces": 4, "tier": "B" }
        },
        {
          "weight": 2,
          "copper": null,
          "silver": null,
          "electrum": null,
          "gold": { "count": 3, "faces": 6, "mult": 100 },
          "platinum": { "count": 1, "faces": 6, "mult": 10 },
          "gems": null,
          "art": { "count": 2, "faces": 4, "tier": "250gp" },
          "magic": null
        }
      ]
    },
    "gems": {
      "10gp": [],
      "50gp": ["Bloodstone", "Carnelian", "Chalcedony"]
    },
    "art": {
      "25gp": ["Silver ewer", "Carved bone statuette"]
    },
    "magic": {
      "A": ["Potion of Healing", "Spell Scroll (cantrip)"],
      "B": ["Potion of Greater Healing"]
    },
    "mundane": [
      { "name": "Backpack", "valueGp": 2 },
      { "name": "Grappling hook", "valueGp": 2 }
    ],
    "mundaneRoll": {
      "1to4": { "count": 1, "faces": 4 },
      "5to10": { "count": 1, "faces": 6 }
    },
    "weapons": [
      { "name": "Longsword", "valueGp": 15 }
    ],
    "weaponsRoll": {
      "1to4": { "count": 1, "faces": 2 }
    },
    "armor": [],
    "armorRoll": {},
    "scrollSpells": {
      "0": ["Fire Bolt", "Light"],
      "1": ["Cure Wounds"]
    }
  })
}

fn full_treasure_profiles() -> Value {
  json!({
    "Dragon hoard": {
      "coinsCount": "more",
      "gemsCount": "more",
      "gemsValue": "higher",
      "artCount": "normal",
      "artValue": "higher",
      "magicCount": "more",
      "magicValue": "normal",
      "mundaneCount": "fewer",
      "weaponsCount": "normal",
      "armorCount": "fewer",
      "hoardToggles": {
        "coinsNone": false,
        "gemsNone": false,
        "artNone": false,
        "magicNone": false,
        "mundaneNone": true,
        "weaponsNone": true,
        "armorNone": true
      },
      "individualToggles": {
        "coinsNone": false,
        "gemsNone": true,
        "artNone": true,
        "magicNone": true,
        "mundaneNone": true,
        "weaponsNone": true,
        "armorNone": true
      },
      "magicScrollChance": 25
    },
    "Pocket bounty": {
      "coinsCount": "fewer",
      "gemsCount": "normal",
      "gemsValue": "lower",
      "artCount": "fewer",
      "artValue": "normal",
      "magicCount": "normal",
      "magicValue": "lower",
      "mundaneCount": "normal",
      "weaponsCount": "normal",
      "armorCount": "normal",
      "hoardToggles": {
        "coinsNone": false,
        "gemsNone": true,
        "artNone": true,
        "magicNone": false,
        "mundaneNone": false,
        "weaponsNone": true,
        "armorNone": true
      },
      "individualToggles": {
        "coinsNone": false,
        "gemsNone": true,
        "artNone": true,
        "magicNone": true,
        "mundaneNone": true,
        "weaponsNone": true,
        "armorNone": true
      },
      "magicScrollChance": 15
    }
  })
}

#[tokio::test]
async fn test_lore_groups_full_payload_round_trips_exactly() {
  assert_exact_roundtrip("/api/lore-groups", full_lore_groups()).await;
}

#[tokio::test]
async fn test_condition_presets_full_payload_round_trips_exactly() {
  assert_exact_roundtrip("/api/condition-presets", full_condition_presets())
    .await;
}

#[tokio::test]
async fn test_save_chain_presets_full_payload_round_trips_exactly() {
  assert_exact_roundtrip("/api/save-chain-presets", full_save_chains()).await;
}

#[tokio::test]
async fn test_treasure_table_full_payload_round_trips_exactly() {
  assert_exact_roundtrip("/api/treasure-table", full_treasure_table()).await;
}

#[tokio::test]
async fn test_treasure_profiles_full_payload_round_trips_exactly() {
  assert_exact_roundtrip("/api/treasure-profiles", full_treasure_profiles())
    .await;
}

#[tokio::test]
async fn test_persisted_empty_collections_read_back_empty_not_null() {
  let dir = TempDir::new().expect("tempdir");
  let state = app_state_for_dir(&dir).await;
  let app = build_test_router(state);
  let cookie = register_and_get_cookie(&app).await;

  // The wire-level empty shape per feature: a list for lore groups,
  // dicts for the preset maps, and the five required-but-empty
  // categories for the treasure table.
  let empty_table = json!({
    "individualBrackets": {},
    "hoardBrackets": {},
    "gems": {},
    "art": {},
    "magic": {}
  });
  for (path, empty) in [
    ("/api/lore-groups", json!([])),
    ("/api/condition-presets", json!({})),
    ("/api/save-chain-presets", json!({})),
    ("/api/treasure-table", empty_table),
    ("/api/treasure-profiles", json!({})),
  ] {
    assert_eq!(
      put_json(&app, &cookie, path, &empty).await,
      StatusCode::OK,
      "PUT {path}"
    );
    assert_eq!(
      get_json(&app, &cookie, path).await,
      empty,
      "GET {path} after an empty PUT must return the empty \
       collection, not null"
    );
  }
}

// ── legacy preset import ────────────────────────────────────────────────────

/// Write the five legacy preset files in historical wire shapes:
/// bool/absent `save_to_end`, the `condition_name` single-effect
/// outcome, int HP amounts, uppercase abilities, lore groups without
/// weight/source/description, condition presets without `category`,
/// and a treasure table predating the seven optional fields.  Also
/// plants an entry for an unknown user and an undecodable payload,
/// both of which must be skipped without aborting the boot.
fn write_legacy_preset_fixtures(dir: &TempDir, user_id: &str) {
  let lore = json!({
    user_id: [
      {
        "id": "grp-wolves",
        "name": "Wolf pack",
        "members": [ { "name": "Wolf" } ]
      }
    ],
    "0000dead-0000-0000-0000-000000000000": [
      { "id": "orphan", "name": "Orphaned", "members": [] }
    ]
  });
  // Missing required fields: undecodable, must be skipped while the
  // other stores import.
  let conditions = json!({
    user_id: { "Bad preset": { "conditionName": "X" } }
  });
  let save_chains = json!({
    user_id: {
      "Old Hold": {
        "name": "Old Hold",
        "save_ability": "WIS",
        "save_dc": 14,
        "on_fail": {
          "hp": { "kind": "damage", "amount": 22 },
          "condition_name": "Paralyzed",
          "condition_note": "legacy note"
        },
        "on_success": {
          "hp": { "kind": "half_fail" },
          "effects": [
            { "name": "Shaken", "save_to_end": true },
            { "name": "Slowed", "note": "half speed", "save_to_end": false }
          ]
        }
      }
    }
  });
  let table = json!({
    user_id: {
      "individualBrackets": {
        "1to4": [
          {
            "weight": 1,
            "copper": { "count": 5, "faces": 6, "mult": 1 },
            "silver": null,
            "electrum": null,
            "gold": null,
            "platinum": null
          }
        ]
      },
      "hoardBrackets": {},
      "gems": { "50gp": ["Onyx"] },
      "art": {},
      "magic": {}
    }
  });
  // Pre-toggle-split flat fields and missing knobs: everything
  // defaults per the Elm decoder.
  let profiles = json!({
    user_id: {
      "Old profile": { "coinsCount": "more", "gemsNone": true }
    }
  });

  for (name, payload) in [
    ("lore-groups.json", &lore),
    ("condition-presets.json", &conditions),
    ("save-chain-presets.json", &save_chains),
    ("treasure-table.json", &table),
    ("treasure-profiles.json", &profiles),
  ] {
    std::fs::write(
      dir.path().join(name),
      serde_json::to_vec_pretty(payload).expect("encode preset fixture"),
    )
    .expect("write preset fixture");
  }
}

#[tokio::test]
async fn test_preset_import_serves_canonical_modern_encoding() {
  let dir = TempDir::new().expect("tempdir");
  let user_id = "37d6a89a-9bb3-4b1b-87ef-6a12d6ce157c";
  write_legacy_fixtures(&dir, user_id);
  write_legacy_preset_fixtures(&dir, user_id);

  let state = app_state_for_dir(&dir).await;
  let app = build_test_router(state);

  let login = app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/auth/login")
        .header("content-type", "application/json")
        .body(Body::from(
          r#"{"email":"legacy@example.com","password":"hunter2hunter"}"#,
        ))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(login.status(), StatusCode::OK);
  let cookie = extract_session_cookie(&login).expect("login cookie");

  // Lore: absent weight/source/description and member role/counts
  // fill in with the Elm decoder's defaults.
  assert_eq!(
    get_json(&app, &cookie, "/api/lore-groups").await,
    json!([
      {
        "id": "grp-wolves",
        "name": "Wolf pack",
        "weight": 3,
        "source": "user",
        "members": [
          { "name": "Wolf", "role": "member", "count_min": 1, "count_max": 1 }
        ],
        "description": ""
      }
    ])
  );

  // Save chains: the legacy condition_name outcome becomes a
  // one-element effects list, bool save_to_end becomes the enum,
  // the int amount is stringified, the ability lowercases.
  assert_eq!(
    get_json(&app, &cookie, "/api/save-chain-presets").await,
    json!({
      "Old Hold": {
        "name": "Old Hold",
        "save_ability": "wis",
        "save_dc": 14,
        "on_fail": {
          "hp": { "kind": "damage", "amount": "22" },
          "effects": [
            { "name": "Paralyzed", "note": "legacy note", "save_to_end": null }
          ]
        },
        "on_success": {
          "hp": { "kind": "half_fail" },
          "effects": [
            { "name": "Shaken", "note": "", "save_to_end": "at_end" },
            { "name": "Slowed", "note": "half speed", "save_to_end": null }
          ]
        }
      }
    })
  );

  // Treasure table: the seven optional fields stay OMITTED so the
  // Elm decoder seeds its bundled defaults, exactly as it would
  // have for the original legacy payload.
  assert_eq!(
    get_json(&app, &cookie, "/api/treasure-table").await,
    json!({
      "individualBrackets": {
        "1to4": [
          {
            "weight": 1,
            "copper": { "count": 5, "faces": 6, "mult": 1 },
            "silver": null,
            "electrum": null,
            "gold": null,
            "platinum": null
          }
        ]
      },
      "hoardBrackets": {},
      "gems": { "50gp": ["Onyx"] },
      "art": {},
      "magic": {}
    })
  );

  // Profiles: unset knobs default; the legacy flat gemsNone lands in
  // hoardToggles; individualToggles takes the constant default.
  assert_eq!(
    get_json(&app, &cookie, "/api/treasure-profiles").await,
    json!({
      "Old profile": {
        "coinsCount": "more",
        "gemsCount": "normal",
        "gemsValue": "normal",
        "artCount": "normal",
        "artValue": "normal",
        "magicCount": "normal",
        "magicValue": "normal",
        "mundaneCount": "normal",
        "weaponsCount": "normal",
        "armorCount": "normal",
        "hoardToggles": {
          "coinsNone": false,
          "gemsNone": true,
          "artNone": false,
          "magicNone": false,
          "mundaneNone": true,
          "weaponsNone": true,
          "armorNone": true
        },
        "individualToggles": {
          "coinsNone": false,
          "gemsNone": true,
          "artNone": true,
          "magicNone": true,
          "mundaneNone": true,
          "weaponsNone": true,
          "armorNone": true
        },
        "magicScrollChance": 15
      }
    })
  );

  // The undecodable condition-preset payload was skipped: the user
  // still reads null (never persisted), and the boot didn't abort.
  let conditions = app
    .clone()
    .oneshot(
      Request::builder()
        .uri("/api/condition-presets")
        .header("cookie", &cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(read_body(conditions).await.trim(), "null");

  // The legacy files are left in place as the rollback copy.
  assert!(dir.path().join("save-chain-presets.json").exists());
  assert!(dir.path().join("lore-groups.json").exists());
}

#[tokio::test]
async fn test_preset_import_runs_only_once() {
  let dir = TempDir::new().expect("tempdir");
  let user_id = "47d6a89a-9bb3-4b1b-87ef-6a12d6ce157c";
  write_legacy_fixtures(&dir, user_id);
  write_legacy_preset_fixtures(&dir, user_id);

  // First boot imports; a second boot must see the marker and leave
  // the rows alone.
  let _first = app_state_for_dir(&dir).await;
  let state = app_state_for_dir(&dir).await;
  let app = build_test_router(state);

  let login = app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/auth/login")
        .header("content-type", "application/json")
        .body(Body::from(
          r#"{"email":"legacy@example.com","password":"hunter2hunter"}"#,
        ))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(login.status(), StatusCode::OK);
  let cookie = extract_session_cookie(&login).expect("login cookie");

  let chains = get_json(&app, &cookie, "/api/save-chain-presets").await;
  assert_eq!(
    chains.as_object().expect("chains object").len(),
    1,
    "re-boot must not duplicate or drop the imported presets"
  );
}
