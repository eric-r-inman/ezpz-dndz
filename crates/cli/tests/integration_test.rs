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
      let stdout = String::from_utf8_lossy(&output.stdout);
      assert!(
        stdout.contains("ezpz-dndz-cli"),
        "Expected version text to contain 'ezpz-dndz-cli', got: {}",
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
fn test_basic_execution() {
  let output = Command::new(get_binary_path()).output();

  match output {
    Ok(output) => {
      assert!(
        output.status.success(),
        "Expected success exit code, got: {:?}\nstderr: {}",
        output.status.code(),
        String::from_utf8_lossy(&output.stderr)
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
fn test_compendium_count_against_tempfile() {
  // Write a small fixture compendium so the command has
  // something to count.  The tempfile shape matches the JSON
  // the server writes to `<data_dir>/compendium/creatures.json`.
  let dir = std::env::temp_dir().join("ezpz-dndz-cli-test");
  std::fs::create_dir_all(&dir).expect("create temp dir");
  let path = dir.join("creatures.json");
  std::fs::write(&path, "[]").expect("write empty fixture");

  let output = Command::new(get_binary_path())
    .args([
      "compendium",
      "count",
      "--path",
      path.to_str().expect("path utf8"),
    ])
    .output()
    .expect("run cli");

  assert!(
    output.status.success(),
    "compendium count failed: stderr={}",
    String::from_utf8_lossy(&output.stderr)
  );
  let stdout = String::from_utf8_lossy(&output.stdout);
  assert!(stdout.contains("0"), "expected count 0 in stdout, got: {stdout}");
}
