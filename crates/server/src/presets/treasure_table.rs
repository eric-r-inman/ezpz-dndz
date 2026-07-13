//! Wire codec + SQL for the singular per-user treasure table.
//!
//! Mirrors `frontend/src/Encounter/Treasure/TableWire.elm`.  The five
//! original categories (`individualBrackets`, `hoardBrackets`,
//! `gems`, `art`, `magic`) are required; a coin formula or hoard
//! sub-roll spec that is absent, null, or malformed decodes as null
//! (the Elm `decodeOptionalField` wraps everything in a fallback).
//!
//! The seven later-added fields (`mundane`, `mundaneRoll`, `weapons`,
//! `weaponsRoll`, `armor`, `armorRoll`, `scrollSpells`) are
//! tri-state: the Elm decoder seeds bundled defaults for an absent
//! (or malformed) field but keeps an explicit empty list as the GM
//! opting out.  The bundled catalog lives only in the frontend, so
//! the server preserves the distinction instead of resolving it: an
//! absent field is stored as absent (`has_*` flag 0) and stays
//! OMITTED in the re-encoding, which makes the Elm decoder seed the
//! same bundled defaults it would have seeded from the original
//! payload.  Tables saved by the current frontend always carry all
//! twelve fields, so their round-trip is exact.

use ezpz_dndz_lib::{db::Db, users::UserId};
use serde_json::{json, Map, Value};
use sqlx::{AnyConnection, Row};
use std::collections::BTreeMap;

use super::{as_object, req_i64};
use crate::per_user_store::PerUserFeature;

pub struct Table {
  pub individual: BTreeMap<String, Vec<IndividualRow>>,
  pub hoard: BTreeMap<String, Vec<HoardRow>>,
  pub gems: BTreeMap<String, Vec<String>>,
  pub art: BTreeMap<String, Vec<String>>,
  pub magic: BTreeMap<String, Vec<String>>,
  pub mundane: Option<Vec<FlatItem>>,
  pub mundane_roll: Option<BTreeMap<String, RollSpec>>,
  pub weapons: Option<Vec<FlatItem>>,
  pub weapons_roll: Option<BTreeMap<String, RollSpec>>,
  pub armor: Option<Vec<FlatItem>>,
  pub armor_roll: Option<BTreeMap<String, RollSpec>>,
  pub scroll_spells: Option<BTreeMap<String, Vec<String>>>,
}

/// A `(count, faces, mult)` coin formula.
pub struct CoinFormula {
  pub count: i64,
  pub faces: i64,
  pub mult: i64,
}

/// A `(count, faces, tier)` gems/art/magic sub-roll spec.
pub struct SubRoll {
  pub count: i64,
  pub faces: i64,
  pub tier: String,
}

pub struct IndividualRow {
  pub weight: i64,
  pub coins: [Option<CoinFormula>; 5],
}

pub struct HoardRow {
  pub weight: i64,
  pub coins: [Option<CoinFormula>; 5],
  pub gems: Option<SubRoll>,
  pub art: Option<SubRoll>,
  pub magic: Option<SubRoll>,
}

pub struct FlatItem {
  pub name: String,
  pub value_gp: i64,
}

pub struct RollSpec {
  pub count: i64,
  pub faces: i64,
}

/// The wire names of the five coin denominations, in encoder order;
/// `coins` arrays above index in this order.
const COIN_KEYS: [&str; 5] =
  ["copper", "silver", "electrum", "gold", "platinum"];

const GEM_TIERS: [&str; 6] =
  ["10gp", "50gp", "100gp", "500gp", "1000gp", "5000gp"];
const ART_TIERS: [&str; 5] = ["25gp", "250gp", "750gp", "2500gp", "7500gp"];
const MAGIC_TABLES: [&str; 9] = ["A", "B", "C", "D", "E", "F", "G", "H", "I"];

/// The treasure-table feature: one table per user.
pub struct TreasureTable;

impl PerUserFeature for TreasureTable {
  const LABEL: &'static str = "treasure-table";
  const PARENT_TABLE: &'static str = "treasure_table_sets";
  type Data = Table;

  fn decode(payload: &Value) -> Result<Self::Data, String> {
    let map = as_object(payload, "treasure table")?;
    Ok(Table {
      individual: decode_dict_list(map, "individualBrackets", |raw, ctx| {
        decode_individual_row(raw, ctx)
      })?,
      hoard: decode_dict_list(map, "hoardBrackets", |raw, ctx| {
        decode_hoard_row(raw, ctx)
      })?,
      gems: decode_dict_list(map, "gems", decode_name)?,
      art: decode_dict_list(map, "art", decode_name)?,
      magic: decode_dict_list(map, "magic", decode_name)?,
      mundane: decode_flat_items(map.get("mundane")),
      mundane_roll: decode_roll_dict(map.get("mundaneRoll")),
      weapons: decode_flat_items(map.get("weapons")),
      weapons_roll: decode_roll_dict(map.get("weaponsRoll")),
      armor: decode_flat_items(map.get("armor")),
      armor_roll: decode_roll_dict(map.get("armorRoll")),
      scroll_spells: decode_scroll_spells(map.get("scrollSpells")),
    })
  }

  fn encode(table: &Table) -> Value {
    let mut out = Map::new();
    out.insert(
      "individualBrackets".to_string(),
      encode_dict_list(&table.individual, encode_individual_row),
    );
    out.insert(
      "hoardBrackets".to_string(),
      encode_dict_list(&table.hoard, encode_hoard_row),
    );
    out.insert("gems".to_string(), encode_dict_list(&table.gems, encode_name));
    out.insert("art".to_string(), encode_dict_list(&table.art, encode_name));
    out
      .insert("magic".to_string(), encode_dict_list(&table.magic, encode_name));
    if let Some(items) = &table.mundane {
      out.insert("mundane".to_string(), encode_flat_items(items));
    }
    if let Some(dict) = &table.mundane_roll {
      out.insert("mundaneRoll".to_string(), encode_roll_dict(dict));
    }
    if let Some(items) = &table.weapons {
      out.insert("weapons".to_string(), encode_flat_items(items));
    }
    if let Some(dict) = &table.weapons_roll {
      out.insert("weaponsRoll".to_string(), encode_roll_dict(dict));
    }
    if let Some(items) = &table.armor {
      out.insert("armor".to_string(), encode_flat_items(items));
    }
    if let Some(dict) = &table.armor_roll {
      out.insert("armorRoll".to_string(), encode_roll_dict(dict));
    }
    if let Some(dict) = &table.scroll_spells {
      out.insert(
        "scrollSpells".to_string(),
        encode_dict_list(dict, encode_name),
      );
    }
    Value::Object(out)
  }

  async fn insert(
    conn: &mut AnyConnection,
    user_id: &UserId,
    table: &Table,
  ) -> Result<(), sqlx::Error> {
    sqlx::query(
      "INSERT INTO treasure_table_sets (user_id, has_mundane, \
       has_mundane_roll, has_weapons, has_weapons_roll, has_armor, \
       has_armor_roll, has_scroll_spells) \
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
    )
    .bind(user_id.as_str())
    .bind(i64::from(table.mundane.is_some()))
    .bind(i64::from(table.mundane_roll.is_some()))
    .bind(i64::from(table.weapons.is_some()))
    .bind(i64::from(table.weapons_roll.is_some()))
    .bind(i64::from(table.armor.is_some()))
    .bind(i64::from(table.armor_roll.is_some()))
    .bind(i64::from(table.scroll_spells.is_some()))
    .execute(&mut *conn)
    .await?;

    // Dict keys survive independently of their (possibly empty) item
    // lists via the brackets presence table.
    let empty = BTreeMap::new();
    for (category, keys) in [
      ("individual", table.individual.keys().collect::<Vec<_>>()),
      ("hoard", table.hoard.keys().collect()),
      ("gems", table.gems.keys().collect()),
      ("art", table.art.keys().collect()),
      ("magic", table.magic.keys().collect()),
      (
        "scrollSpells",
        table
          .scroll_spells
          .as_ref()
          .unwrap_or(&empty)
          .keys()
          .collect(),
      ),
    ] {
      for bracket in keys {
        sqlx::query(
          "INSERT INTO treasure_table_brackets (user_id, category, \
           bracket) VALUES ($1, $2, $3)",
        )
        .bind(user_id.as_str())
        .bind(category)
        .bind(bracket)
        .execute(&mut *conn)
        .await?;
      }
    }

    for (bracket, rows) in &table.individual {
      for (i, row) in rows.iter().enumerate() {
        insert_coin_row(
          conn,
          "INSERT INTO treasure_individual_rows (user_id, bracket, \
           position, weight, copper_count, copper_faces, copper_mult, \
           silver_count, silver_faces, silver_mult, electrum_count, \
           electrum_faces, electrum_mult, gold_count, gold_faces, \
           gold_mult, platinum_count, platinum_faces, platinum_mult) \
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, \
           $13, $14, $15, $16, $17, $18, $19)",
          user_id,
          bracket,
          i as i64,
          row.weight,
          &row.coins,
          None,
        )
        .await?;
      }
    }

    for (bracket, rows) in &table.hoard {
      for (i, row) in rows.iter().enumerate() {
        insert_coin_row(
          conn,
          "INSERT INTO treasure_hoard_rows (user_id, bracket, \
           position, weight, copper_count, copper_faces, copper_mult, \
           silver_count, silver_faces, silver_mult, electrum_count, \
           electrum_faces, electrum_mult, gold_count, gold_faces, \
           gold_mult, platinum_count, platinum_faces, platinum_mult, \
           gems_count, gems_faces, gems_tier, art_count, art_faces, \
           art_tier, magic_count, magic_faces, magic_table_key) \
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, \
           $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, \
           $24, $25, $26, $27, $28)",
          user_id,
          bracket,
          i as i64,
          row.weight,
          &row.coins,
          Some((&row.gems, &row.art, &row.magic)),
        )
        .await?;
      }
    }

    for (category, dict) in [
      ("gems", Some(&table.gems)),
      ("art", Some(&table.art)),
      ("magic", Some(&table.magic)),
      ("scrollSpells", table.scroll_spells.as_ref()),
    ] {
      let Some(dict) = dict else { continue };
      for (bracket, names) in dict {
        for (i, name) in names.iter().enumerate() {
          sqlx::query(
            "INSERT INTO treasure_name_entries (user_id, category, \
             bracket, position, name) VALUES ($1, $2, $3, $4, $5)",
          )
          .bind(user_id.as_str())
          .bind(category)
          .bind(bracket)
          .bind(i as i64)
          .bind(name)
          .execute(&mut *conn)
          .await?;
        }
      }
    }

    for (category, items) in [
      ("mundane", table.mundane.as_ref()),
      ("weapons", table.weapons.as_ref()),
      ("armor", table.armor.as_ref()),
    ] {
      let Some(items) = items else { continue };
      for (i, item) in items.iter().enumerate() {
        sqlx::query(
          "INSERT INTO treasure_flat_items (user_id, category, \
           position, name, value_gp) VALUES ($1, $2, $3, $4, $5)",
        )
        .bind(user_id.as_str())
        .bind(category)
        .bind(i as i64)
        .bind(&item.name)
        .bind(item.value_gp)
        .execute(&mut *conn)
        .await?;
      }
    }

    for (category, dict) in [
      ("mundane", table.mundane_roll.as_ref()),
      ("weapons", table.weapons_roll.as_ref()),
      ("armor", table.armor_roll.as_ref()),
    ] {
      let Some(dict) = dict else { continue };
      for (bracket, spec) in dict {
        sqlx::query(
          "INSERT INTO treasure_roll_specs (user_id, category, \
           bracket, die_count, die_faces) VALUES ($1, $2, $3, $4, $5)",
        )
        .bind(user_id.as_str())
        .bind(category)
        .bind(bracket)
        .bind(spec.count)
        .bind(spec.faces)
        .execute(&mut *conn)
        .await?;
      }
    }

    Ok(())
  }

  async fn fetch(
    db: &Db,
    user_id: &UserId,
  ) -> Result<Option<Self::Data>, sqlx::Error> {
    let Some(parent) = sqlx::query(
      "SELECT has_mundane, has_mundane_roll, has_weapons, \
       has_weapons_roll, has_armor, has_armor_roll, has_scroll_spells \
       FROM treasure_table_sets WHERE user_id = $1",
    )
    .bind(user_id.as_str())
    .fetch_optional(db.pool())
    .await?
    else {
      return Ok(None);
    };

    let flag = |col: &str| -> Result<bool, sqlx::Error> {
      Ok(parent.try_get::<i64, _>(col)? != 0)
    };
    let mut table = Table {
      individual: BTreeMap::new(),
      hoard: BTreeMap::new(),
      gems: BTreeMap::new(),
      art: BTreeMap::new(),
      magic: BTreeMap::new(),
      mundane: flag("has_mundane")?.then(Vec::new),
      mundane_roll: flag("has_mundane_roll")?.then(BTreeMap::new),
      weapons: flag("has_weapons")?.then(Vec::new),
      weapons_roll: flag("has_weapons_roll")?.then(BTreeMap::new),
      armor: flag("has_armor")?.then(Vec::new),
      armor_roll: flag("has_armor_roll")?.then(BTreeMap::new),
      scroll_spells: flag("has_scroll_spells")?.then(BTreeMap::new),
    };

    // Seed every persisted dict key first so brackets whose lists the
    // GM emptied still appear in the encoding.
    for row in sqlx::query(
      "SELECT category, bracket FROM treasure_table_brackets \
       WHERE user_id = $1",
    )
    .bind(user_id.as_str())
    .fetch_all(db.pool())
    .await?
    {
      let category: String = row.try_get("category")?;
      let bracket: String = row.try_get("bracket")?;
      match category.as_str() {
        "individual" => {
          table.individual.entry(bracket).or_default();
        }
        "hoard" => {
          table.hoard.entry(bracket).or_default();
        }
        "gems" => {
          table.gems.entry(bracket).or_default();
        }
        "art" => {
          table.art.entry(bracket).or_default();
        }
        "magic" => {
          table.magic.entry(bracket).or_default();
        }
        "scrollSpells" => {
          if let Some(dict) = table.scroll_spells.as_mut() {
            dict.entry(bracket).or_default();
          }
        }
        _ => {}
      }
    }

    for row in sqlx::query(
      "SELECT * FROM treasure_individual_rows WHERE user_id = $1 \
       ORDER BY bracket, position",
    )
    .bind(user_id.as_str())
    .fetch_all(db.pool())
    .await?
    {
      let bracket: String = row.try_get("bracket")?;
      table
        .individual
        .entry(bracket)
        .or_default()
        .push(IndividualRow {
          weight: row.try_get("weight")?,
          coins: coins_from_row(&row)?,
        });
    }

    for row in sqlx::query(
      "SELECT * FROM treasure_hoard_rows WHERE user_id = $1 \
       ORDER BY bracket, position",
    )
    .bind(user_id.as_str())
    .fetch_all(db.pool())
    .await?
    {
      let bracket: String = row.try_get("bracket")?;
      table.hoard.entry(bracket).or_default().push(HoardRow {
        weight: row.try_get("weight")?,
        coins: coins_from_row(&row)?,
        gems: sub_roll_from_row(&row, "gems_count", "gems_faces", "gems_tier")?,
        art: sub_roll_from_row(&row, "art_count", "art_faces", "art_tier")?,
        magic: sub_roll_from_row(
          &row,
          "magic_count",
          "magic_faces",
          "magic_table_key",
        )?,
      });
    }

    for row in sqlx::query(
      "SELECT category, bracket, name FROM treasure_name_entries \
       WHERE user_id = $1 ORDER BY bracket, position",
    )
    .bind(user_id.as_str())
    .fetch_all(db.pool())
    .await?
    {
      let category: String = row.try_get("category")?;
      let bracket: String = row.try_get("bracket")?;
      let name: String = row.try_get("name")?;
      let dict = match category.as_str() {
        "gems" => Some(&mut table.gems),
        "art" => Some(&mut table.art),
        "magic" => Some(&mut table.magic),
        "scrollSpells" => table.scroll_spells.as_mut(),
        _ => None,
      };
      if let Some(dict) = dict {
        dict.entry(bracket).or_default().push(name);
      }
    }

    for row in sqlx::query(
      "SELECT category, position, name, value_gp FROM \
       treasure_flat_items WHERE user_id = $1 ORDER BY position",
    )
    .bind(user_id.as_str())
    .fetch_all(db.pool())
    .await?
    {
      let category: String = row.try_get("category")?;
      let item = FlatItem {
        name: row.try_get("name")?,
        value_gp: row.try_get("value_gp")?,
      };
      let items = match category.as_str() {
        "mundane" => table.mundane.as_mut(),
        "weapons" => table.weapons.as_mut(),
        "armor" => table.armor.as_mut(),
        _ => None,
      };
      if let Some(items) = items {
        items.push(item);
      }
    }

    for row in sqlx::query(
      "SELECT category, bracket, die_count, die_faces FROM \
       treasure_roll_specs WHERE user_id = $1",
    )
    .bind(user_id.as_str())
    .fetch_all(db.pool())
    .await?
    {
      let category: String = row.try_get("category")?;
      let bracket: String = row.try_get("bracket")?;
      let spec = RollSpec {
        count: row.try_get("die_count")?,
        faces: row.try_get("die_faces")?,
      };
      let dict = match category.as_str() {
        "mundane" => table.mundane_roll.as_mut(),
        "weapons" => table.weapons_roll.as_mut(),
        "armor" => table.armor_roll.as_mut(),
        _ => None,
      };
      if let Some(dict) = dict {
        dict.insert(bracket, spec);
      }
    }

    Ok(Some(table))
  }
}

// ── row plumbing ─────────────────────────────────────────────────────────────

/// Insert one individual or hoard row: the shared 4 + 15 columns,
/// plus the three hoard sub-roll triples when given.
#[allow(clippy::too_many_arguments)]
async fn insert_coin_row(
  conn: &mut AnyConnection,
  sql: &str,
  user_id: &UserId,
  bracket: &str,
  position: i64,
  weight: i64,
  coins: &[Option<CoinFormula>; 5],
  specs: Option<(&Option<SubRoll>, &Option<SubRoll>, &Option<SubRoll>)>,
) -> Result<(), sqlx::Error> {
  let mut query = sqlx::query(sql)
    .bind(user_id.as_str())
    .bind(bracket.to_string())
    .bind(position)
    .bind(weight);
  for coin in coins {
    query = query
      .bind(coin.as_ref().map(|c| c.count))
      .bind(coin.as_ref().map(|c| c.faces))
      .bind(coin.as_ref().map(|c| c.mult));
  }
  if let Some((gems, art, magic)) = specs {
    for spec in [gems, art, magic] {
      query = query
        .bind(spec.as_ref().map(|s| s.count))
        .bind(spec.as_ref().map(|s| s.faces))
        .bind(spec.as_ref().map(|s| s.tier.clone()));
    }
  }
  query.execute(conn).await.map(|_| ())
}

fn coins_from_row(
  row: &sqlx::any::AnyRow,
) -> Result<[Option<CoinFormula>; 5], sqlx::Error> {
  let coin = |prefix: &str| -> Result<Option<CoinFormula>, sqlx::Error> {
    row
      .try_get::<Option<i64>, _>(format!("{prefix}_count").as_str())?
      .map(|count| {
        Ok::<_, sqlx::Error>(CoinFormula {
          count,
          faces: row
            .try_get::<Option<i64>, _>(format!("{prefix}_faces").as_str())?
            .unwrap_or(0),
          mult: row
            .try_get::<Option<i64>, _>(format!("{prefix}_mult").as_str())?
            .unwrap_or(0),
        })
      })
      .transpose()
  };
  Ok([
    coin("copper")?,
    coin("silver")?,
    coin("electrum")?,
    coin("gold")?,
    coin("platinum")?,
  ])
}

fn sub_roll_from_row(
  row: &sqlx::any::AnyRow,
  count_col: &str,
  faces_col: &str,
  tier_col: &str,
) -> Result<Option<SubRoll>, sqlx::Error> {
  row
    .try_get::<Option<i64>, _>(count_col)?
    .map(|count| {
      Ok(SubRoll {
        count,
        faces: row.try_get::<Option<i64>, _>(faces_col)?.unwrap_or(0),
        tier: row
          .try_get::<Option<String>, _>(tier_col)?
          .unwrap_or_default(),
      })
    })
    .transpose()
}

// ── decode ───────────────────────────────────────────────────────────────────

/// A required `Dict String (List a)` field, like the Elm
/// `D.field name (decodeDictList item)`: any failing item fails the
/// payload.
fn decode_dict_list<T>(
  map: &Map<String, Value>,
  key: &str,
  item: impl Fn(&Value, &str) -> Result<T, String>,
) -> Result<BTreeMap<String, Vec<T>>, String> {
  as_object(
    map
      .get(key)
      .ok_or_else(|| format!("missing required field {key:?}"))?,
    &format!("field {key:?}"),
  )?
  .iter()
  .map(|(bracket, raw_list)| {
    let context = format!("{key}[{bracket:?}]");
    let items = raw_list
      .as_array()
      .ok_or_else(|| format!("{context}: expected an array"))?
      .iter()
      .enumerate()
      .map(|(i, raw)| item(raw, &format!("{context}[{i}]")))
      .collect::<Result<Vec<_>, _>>()?;
    Ok((bracket.clone(), items))
  })
  .collect()
}

fn decode_name(raw: &Value, context: &str) -> Result<String, String> {
  raw
    .as_str()
    .map(str::to_string)
    .ok_or_else(|| format!("{context}: expected a string"))
}

fn decode_individual_row(
  raw: &Value,
  context: &str,
) -> Result<IndividualRow, String> {
  let map = as_object(raw, context)?;
  Ok(IndividualRow {
    weight: req_i64(map, "weight", context)?,
    coins: decode_coins(map),
  })
}

fn decode_hoard_row(raw: &Value, context: &str) -> Result<HoardRow, String> {
  let map = as_object(raw, context)?;
  Ok(HoardRow {
    weight: req_i64(map, "weight", context)?,
    coins: decode_coins(map),
    gems: decode_sub_roll(map.get("gems"), &GEM_TIERS),
    art: decode_sub_roll(map.get("art"), &ART_TIERS),
    magic: decode_sub_roll(map.get("magic"), &MAGIC_TABLES),
  })
}

fn decode_coins(map: &Map<String, Value>) -> [Option<CoinFormula>; 5] {
  COIN_KEYS.map(|key| decode_coin(map.get(key)))
}

/// `decodeOptionalField name decodeCoinFormula`: absent, null, and a
/// malformed value all decode as `None`.
fn decode_coin(raw: Option<&Value>) -> Option<CoinFormula> {
  let map = raw?.as_object()?;
  Some(CoinFormula {
    count: map.get("count").and_then(Value::as_i64)?,
    faces: map.get("faces").and_then(Value::as_i64)?,
    mult: map.get("mult").and_then(Value::as_i64)?,
  })
}

/// `decodeOptionalField name (decodeSpec tierDecoder)`: an unknown
/// tier token fails the spec, which the optional wrapper turns into
/// `None` — exactly the Elm behavior.
fn decode_sub_roll(
  raw: Option<&Value>,
  valid_tiers: &[&str],
) -> Option<SubRoll> {
  let map = raw?.as_object()?;
  let tier = map.get("tier").and_then(Value::as_str)?;
  if !valid_tiers.contains(&tier) {
    return None;
  }
  Some(SubRoll {
    count: map.get("count").and_then(Value::as_i64)?,
    faces: map.get("faces").and_then(Value::as_i64)?,
    tier: tier.to_string(),
  })
}

/// A tri-state flat-item list: `None` when the field is absent or
/// malformed (the Elm decoder would seed bundled defaults),
/// `Some(items)` when it parses.
fn decode_flat_items(raw: Option<&Value>) -> Option<Vec<FlatItem>> {
  raw?
    .as_array()?
    .iter()
    .map(|item| {
      let map = item.as_object()?;
      Some(FlatItem {
        name: map.get("name").and_then(Value::as_str)?.to_string(),
        value_gp: map.get("valueGp").and_then(Value::as_i64)?,
      })
    })
    .collect()
}

/// A tri-state per-bracket roll dict, same fallback rules.
fn decode_roll_dict(raw: Option<&Value>) -> Option<BTreeMap<String, RollSpec>> {
  raw?
    .as_object()?
    .iter()
    .map(|(bracket, spec)| {
      let map = spec.as_object()?;
      Some((
        bracket.clone(),
        RollSpec {
          count: map.get("count").and_then(Value::as_i64)?,
          faces: map.get("faces").and_then(Value::as_i64)?,
        },
      ))
    })
    .collect()
}

/// A tri-state string-list dict (`scrollSpells`), same fallback
/// rules.
fn decode_scroll_spells(
  raw: Option<&Value>,
) -> Option<BTreeMap<String, Vec<String>>> {
  raw?
    .as_object()?
    .iter()
    .map(|(bracket, raw_list)| {
      let names = raw_list
        .as_array()?
        .iter()
        .map(|v| v.as_str().map(str::to_string))
        .collect::<Option<Vec<_>>>()?;
      Some((bracket.clone(), names))
    })
    .collect()
}

// ── encode ───────────────────────────────────────────────────────────────────

fn encode_dict_list<T>(
  dict: &BTreeMap<String, Vec<T>>,
  item: impl Fn(&T) -> Value,
) -> Value {
  Value::Object(
    dict
      .iter()
      .map(|(bracket, items)| {
        (bracket.clone(), Value::Array(items.iter().map(&item).collect()))
      })
      .collect(),
  )
}

// `&String` (not `&str`) because this is passed as the item encoder
// for `encode_dict_list::<String>`, whose callback receives `&T`.
#[allow(clippy::ptr_arg)]
fn encode_name(name: &String) -> Value {
  Value::String(name.clone())
}

fn encode_individual_row(row: &IndividualRow) -> Value {
  Value::Object(coin_fields(row.weight, &row.coins))
}

fn encode_hoard_row(row: &HoardRow) -> Value {
  let mut fields = coin_fields(row.weight, &row.coins);
  fields.insert("gems".to_string(), encode_sub_roll(&row.gems));
  fields.insert("art".to_string(), encode_sub_roll(&row.art));
  fields.insert("magic".to_string(), encode_sub_roll(&row.magic));
  Value::Object(fields)
}

/// The shared `{weight, copper, …, platinum}` fields; each coin is a
/// `{count, faces, mult}` object or literal null, as the Elm encoder
/// always emits all five denominations.
fn coin_fields(
  weight: i64,
  coins: &[Option<CoinFormula>; 5],
) -> Map<String, Value> {
  let mut fields = Map::new();
  fields.insert("weight".to_string(), json!(weight));
  for (key, coin) in COIN_KEYS.iter().zip(coins) {
    fields.insert(
      (*key).to_string(),
      coin.as_ref().map_or(
        Value::Null,
        |c| json!({ "count": c.count, "faces": c.faces, "mult": c.mult }),
      ),
    );
  }
  fields
}

fn encode_sub_roll(spec: &Option<SubRoll>) -> Value {
  spec.as_ref().map_or(
    Value::Null,
    |s| json!({ "count": s.count, "faces": s.faces, "tier": s.tier }),
  )
}

fn encode_flat_items(items: &[FlatItem]) -> Value {
  Value::Array(
    items
      .iter()
      .map(|item| json!({ "name": item.name, "valueGp": item.value_gp }))
      .collect(),
  )
}

fn encode_roll_dict(dict: &BTreeMap<String, RollSpec>) -> Value {
  Value::Object(
    dict
      .iter()
      .map(|(bracket, spec)| {
        (bracket.clone(), json!({ "count": spec.count, "faces": spec.faces }))
      })
      .collect(),
  )
}
