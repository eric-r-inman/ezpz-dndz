#+title:     LLMs
#+language:  en

* Server crate: role and scope

The =crates/server= crate is the project's general-purpose long-running
service.  It is /not/ specifically an HTTP server — HTTP is present
only as infrastructure for health checks, metrics, and observability.

The server might primarily:

- Watch local files for changes and react to them.
- Communicate over a binary protocol, gRPC, or WebSockets.
- Bridge between systems (queues, databases, external APIs).
- Serve any other role that calls for a persistent process responding
  to stimuli.

When adding new functionality that requires a long-running process,
build it in the server crate rather than creating a separate service.
The server already provides structured logging, systemd socket
activation, watchdog integration, graceful shutdown, and an Elm
frontend — duplicating this infrastructure is wasteful and
error-prone.

Do not mistake the server for "just a web server" and stand up a
separate HTTP service from scratch.  The existing HTTP routes
(=/healthz=, =/metrics=, =/me=, =/scalar=) are supporting
infrastructure, not the defining purpose.

* General code guidelines

These are instructions for LLMs to write code more to my liking.
The companion file =llms.org= mirrors the template's own LLM
guidance — most notably the no-=unwrap=/=expect= rule for shipping
Rust code, enforced in CI via clippy =-D warnings= and the
workspace-level =deny= block.  Read it alongside this file.

** Documents

When authoring new content, make them ~org-mode~ files.

Use ~:exports code~ if you just want to show off the code, and don't want it to
actually run anything.

No file lists in documentation.

** Comments

*** Formatting and punctuation

Comments must be complete sentences, wrapped at ~80 columns~, with standard
punctuation.

*** Content

Only comment non-obvious intent, invariants, tradeoffs, or historical
constraints; no restating of control flow.

** Code

*** Initialisms

Use Pascal Initialisms (~Url~) instead of Preserved Initialisms (~URL~) when
_authoring_ new identifiers in camel case.

** Rust

*** Error Handling

Prefer semantic errors.  Do not just wrap or propagate a ~FileMissingError~ or
~FileWriteError~.  This information _might_ include what file was involved, but
it doesn't say what was happening.  Include something either about the error
itself (like ~ConfigFileMissingError~) or about the process in which the error
occurred (~ReportFileWriteError~).

In cases where you can be semantic with your approach to APIs, use ~thiserror~
to automatically map API errors of certain kinds to semantic errors.

A bad example.  This is bad because it simply signals that a file somewhere in
the program couldn't be read — this could be any file, and tells contributors
and users nothing:

#+begin_src rustic :results none :exports code
use std::fs;
use thiserror::Error;

enum AppError {
  #[error("Could not read file: {0}")]
  FileReadError(#[from] std::io::Error),
}

fn config_file_contents() -> Result<String, AppError> {
  fs::read_to_string(file_path)
    .map_err(AppError::FileReadError)
}
#+end_src

The following is a good example, where the error indicates the nature of the
failure (the file could not be read) and the context (which file/operation):

#+begin_src rustic :results none :exports code
use std::fs;
use thiserror::Error;

enum AppError {
  #[error("Could not read configuration file: {0}")]
  ConfigFileReadError(#[from] std::io::Error),
}

fn config_file_contents() -> Result<String, AppError> {
  fs::read_to_string(file_path)
    .map_err(AppError::ConfigFileReadError)
}
#+end_src

Generally this means there will be little reuse of error variants, and that is
acceptable.  Do not swallow errors — let them propagate.

*** Code Structure

**** Files and modules

~main.rs~ should only ever be an orchestrator.  Create sibling files for
associated functionality and have ~main.rs~ delegate to them.

Delegate obvious concerns: ~config.rs~ for configuration, ~logging.rs~ for
logging initialization.  It is okay if these wind up being a single struct and
a single function.

Keep ~.rs~ files under ~src~ for executables and ~lib~ for libraries.

**** Chains, local variables, and tap

Local variables should be generally frowned upon unless Rust specifically
requires them (for scope/ownership reasons), or a value has multiple uses.

You can further avoid local variables by using the ~tap~ crate to do logging in
the middle of a call chain without breaking the chain.

Another way to avoid local variables is to create structs atomically from
function calls.  The ~foo~ field can be assigned the result of the ~foo()~
call, for example.  Prefer nouns (~foo()~) over verb-prefixed names
(~get_foo()~), since verbs are highly subjective in software.

Prefer functional combinators over explicit ~loop~ and early ~return~.  When
functions grow complicated, simplify by extracting smaller functions.

*** Debugging

When lacking information during debugging, permanent additions to the logs (at
appropriate levels) are one of the best cures.  The program should tell you
what ails it.

Create tests which exercise the problem you are running into.  Prefer mock
services with integration tests so we can test real behavior, over unit tests
which test contrived situations.

Tests and test scripts must exit with a proper error code.

*** Types as validation

Only use ~Option~ if the field is truly optional.  If a struct would be invalid
without a field set, do not use ~Option~.  Instead, make an intermediate type
that represents a candidate whose validity is not yet fully known.  This is
very helpful for processing phases.

For example, ~CliArgs~ can represent arguments as provided on the command line.
~ConfigFile~ can represent the configuration file's state.  Meshing the two
together yields a ~Config~ that represents a completely valid configuration.

* Verification

** Use the Nix development shell when available

If ~nix~ is available (~which nix~ succeeds), run all ~cargo~ commands inside
the Nix development shell rather than using whatever ~cargo~ is on the system
PATH:

#+begin_src sh :results none :exports code
nix develop --command cargo build --workspace
nix develop --command cargo test --workspace
#+end_src

This ensures the correct Rust toolchain and associated tools (such as
~rustfmt~) are in use.  The pre-commit hook requires ~rustfmt~ in PATH, so
~git commit~ must also go through the shell:

#+begin_src sh :results none :exports code
nix develop --command git commit -m "your message"
#+end_src

** Run all tests after changes

Run ~cargo test --workspace~ after making any change to verify nothing is
broken.

* Frontend layering

The Elm frontend has a strict separation between domain logic and view
code; see [[file:docs/ARCHITECTURE.org][docs/ARCHITECTURE.org]] for the full discussion.

- ~frontend/src/Encounter.elm~ owns all D&D rules: types (=Creature=,
  =Cover=, =Encounter=), seed data, and pure functions like =nextTurn=
  and =mapCreature=.  It must not import =Html=, =Browser=, =Url=, or
  any rendering primitive.
- ~frontend/src/Main.elm~ is the application shell: =Browser.application=,
  =main= / =subscriptions= / =init= / =update= dispatch table / =view=
  composition / =viewPage= route dispatcher.  It must NOT grow inline
  view trees, helper functions, or update logic — those live in
  =View/*= and =Update/*= modules.
- A =Msg= branch in =updateInner= must be a one-liner that delegates
  to ~Update.Foo.bar~.  If the branch starts walking the queue,
  comparing initiative, or doing HP arithmetic, the work belongs in
  =Encounter= or =HpChange=.

This split is what lets us add alternate UI layouts (e.g. an upcoming
"simple view") without rewriting rules.

* When adding new features

When adding a new feature to the project, the new code and structure
*follow the architectural structure* — or, if a clean fit doesn't
exist yet, embrace the *ideals* of the structure.  The shape is
already there; extend it, don't recreate it.

For a new modal feature, the canonical layout is:

  - Domain rules → =Foo.elm= or =Encounter/Foo.elm= (pure; no =Html=).
  - UI substate → =Ui/Foo.elm= (record alias + ~fresh~ constructor).
  - Update branches → =Update/Foo.elm= (one function per Msg branch,
    pattern-matching on the ~Modal~ ADT).
  - Modal ADT → add ~ModalFoo FooUi~ to ~Modal~ in =Model.elm=; do
    NOT add a separate ~Maybe FooUi~ field on ~Model~.
  - View → =View/Modal/Foo.elm= (entry point pattern-matches on
    ~model.modal~).
  - Cmd helpers → =Effects.elm= or =Util/Http.elm=.  Update modules
    don't ~import Http~ directly.
  - Wire the dispatch as one-liners in =Main=' s =view= and
    =updateInner=.

For a new backend feature: =JsonFileStore<T>= for persistence,
=aide::ApiRouter= for routes, semantic ~thiserror~ variants naming
the operation.  CLI subcommands each go in =crates/cli/src/foo.rs=.

See [[file:docs/ARCHITECTURE.org][docs/ARCHITECTURE.org]] for the full pattern with examples.

The honest version: if you're tempted to write a one-off helper
inline in =Main.elm=, stop — find the right home first.  The
structure isn't decoration; it's load-bearing for swappable UI
layouts and for the modal-state invariants the type system enforces.

* Frozen / archived planning docs

=docs/archive/= holds historical planning documents
(=OPTIMIZATION_AND_COMPLIANCE_PLAN.org=, =ROADMAP.md=,
=COMPENDIUM_PLAN.org=, =CHANGELOG.org=, plus the locally-
preserved-but-untracked =MODULARIZATION_PLAN.org=,
=COMPLIANCE_PLAN.org=, and =TOOLTIPS.org=).  They are no longer
maintained and should not be read or updated.  Instructions
inside that say "update X" are stale.

For project status / structure, consult [[file:docs/ARCHITECTURE.org][docs/ARCHITECTURE.org]] —
the load-bearing decisions live there.  Live planning docs
that ARE current: [[file:docs/AUTH_TESTING.org][docs/AUTH_TESTING.org]] (local-dev account
flows) and [[file:docs/systemd.org][docs/systemd.org]] (LoadCredential / secret passing).

* Changelog: don't.

The project does not maintain a =CHANGELOG.org= /
=CHANGELOG.md=.  Don't create one, don't update one if you find
one (the legacy file lives in =docs/archive/CHANGELOG.org= for
historical reference only).  Commit messages and the git log are
the canonical record of what changed; ARCHITECTURE.org captures
the load-bearing decisions.  If you want to summarize a change
for the user, do it in the chat reply — not in a tracked doc.
