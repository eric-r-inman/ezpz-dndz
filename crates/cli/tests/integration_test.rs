use std::{path::PathBuf, process::Command};

// `allow-expect-in-tests` only covers items inside `#[test]` /
// `#[cfg(test)]` modules; this helper is at crate scope, hence the
// localized override.  Any failure here means the test harness is
// fundamentally broken — panicking is the correct response.
#[allow(clippy::expect_used)]
fn get_binary_path() -> PathBuf {
  let mut path =
    std::env::current_exe().expect("Failed to get current executable path");

  // Navigate from the test executable to the binary
  path.pop(); // remove test executable name
  path.pop(); // remove deps dir
  path.push("ezpz-dndz-cli");

  // If the binary doesn't exist in release, try debug
  if !path.exists() {
    path.pop();
    path.pop();
    path.push("debug");
    path.push("ezpz-dndz-cli");
  }

  path
}

#[test]
fn test_help_flag() {
  let output = Command::new(get_binary_path()).arg("--help").output();

  match output {
    Ok(output) => {
      assert!(
        output.status.success(),
        "Expected success exit code, got: {:?}",
        output.status.code()
      );
      let stdout = String::from_utf8_lossy(&output.stdout);
      assert!(
        stdout.contains("Usage:"),
        "Expected help text to contain 'Usage:', got: {}",
        stdout
      );
    }
    Err(e) => {
      if e.kind() == std::io::ErrorKind::NotFound {
        eprintln!(
                    "Binary not found. Please build the project first with: cargo build -p ezpz-dndz-cli"
                );
      }
      panic!("Failed to execute binary: {}", e);
    }
  }
}

#[test]
fn test_version_flag() {
  let output = Command::new(get_binary_path()).arg("--version").output();

  match output {
    Ok(output) => {
      assert!(
        output.status.success(),
        "Expected success exit code, got: {:?}",
        output.status.code()
      );
      // `MergeConfig`'s `app_name = "ezpz-dndz"` becomes the clap
      // command name, so `--version` prints `ezpz-dndz <ver>` rather
      // than the binary basename `ezpz-dndz-cli`.
      let stdout = String::from_utf8_lossy(&output.stdout);
      assert!(
        stdout.contains("ezpz-dndz"),
        "Expected version text to contain 'ezpz-dndz', got: {}",
        stdout
      );
    }
    Err(e) => {
      if e.kind() == std::io::ErrorKind::NotFound {
        eprintln!(
                    "Binary not found. Please build the project first with: cargo build -p ezpz-dndz-cli"
                );
      }
      panic!("Failed to execute binary: {}", e);
    }
  }
}

#[test]
fn test_no_subcommand_is_a_usage_error() {
  let output = Command::new(get_binary_path()).output();

  match output {
    Ok(output) => {
      assert_eq!(
        output.status.code(),
        Some(2),
        "Expected the usage-error exit code\nstderr: {}",
        String::from_utf8_lossy(&output.stderr)
      );
      assert!(
        String::from_utf8_lossy(&output.stderr)
          .contains("Usage: ezpz-dndz-cli"),
        "Expected clap's usage on stderr"
      );
    }
    Err(e) => {
      if e.kind() == std::io::ErrorKind::NotFound {
        eprintln!(
                    "Binary not found. Please build the project first with: cargo build -p ezpz-dndz-cli"
                );
      }
      panic!("Failed to execute binary: {}", e);
    }
  }
}

#[test]
fn test_dice_clear_without_yes_fails_and_says_why() {
  let dir = std::env::temp_dir()
    .join(format!("ezpz-dndz-cli-test-{}", uuid::Uuid::new_v4()));
  let output = Command::new(get_binary_path())
    .args([
      "dice",
      "clear",
      "--email",
      "dm@example.com",
      "--data-dir",
      dir.to_str().expect("path utf8"),
    ])
    .output()
    .expect("run cli");
  assert!(!output.status.success(), "clear without --yes should fail");
  assert!(
    String::from_utf8_lossy(&output.stderr).contains("--yes"),
    "the failure should name --yes"
  );
}

#[test]
fn test_compendium_count_against_tempfile() {
  // `count` only reads.  It refuses a data dir with no database and
  // creates nothing there.  Once the database exists, an empty one
  // holds no user-owned creatures, so the count is 0.
  let dir = std::env::temp_dir()
    .join(format!("ezpz-dndz-cli-test-{}", uuid::Uuid::new_v4()));
  let count = || {
    Command::new(get_binary_path())
      .args([
        "compendium",
        "count",
        "--data-dir",
        dir.to_str().expect("path utf8"),
      ])
      .output()
      .expect("run cli")
  };

  assert!(
    !count().status.success(),
    "count should refuse a data dir with no database"
  );
  assert!(!dir.exists(), "count should create nothing");

  tokio::runtime::Builder::new_current_thread()
    .enable_all()
    .build()
    .expect("build a runtime")
    .block_on(ezpz_dndz_lib::db::Db::connect(
      &ezpz_dndz_lib::db::default_sqlite_url(&dir),
    ))
    .expect("create the database");

  let output = count();
  assert!(
    output.status.success(),
    "compendium count failed: stderr={}",
    String::from_utf8_lossy(&output.stderr)
  );
  let stdout = String::from_utf8_lossy(&output.stdout);
  assert!(stdout.contains("0"), "expected count 0 in stdout, got: {stdout}");
  std::fs::remove_dir_all(&dir).expect("remove the scratch data dir");
}
