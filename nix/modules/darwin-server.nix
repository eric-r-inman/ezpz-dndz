# Darwin (macOS/launchd) module for the ezpz-dndz-server service.
# Thin wrapper around the foundation's mkDarwinService helper.
# See nixos-server.nix for the Linux/systemd equivalent.
#
# Minimal usage (defaults to Unix domain socket):
#
#   inputs.ezpz-dndz.darwinModules.server
#
#   services.ezpz-dndz-server = {
#     enable = true;
#   };
#
# To use TCP instead:
#
#   services.ezpz-dndz-server = {
#     enable = true;
#     socket = null;
#     port   = 8080;
#   };
#
# To enable health checking (requires a reachable health endpoint):
#
#   services.ezpz-dndz-server = {
#     enable = true;
#     healthCheck.enable = true;
#     healthCheck.url = "http://127.0.0.1:3000/healthz";
#   };
{
  self,
  foundation,
}:
foundation.lib.mkDarwinService {
  name = "ezpz-dndz-server";
  inherit self;
}
