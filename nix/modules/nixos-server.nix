# NixOS (Linux/systemd) module for the ezpz-dndz-server service.
# Thin wrapper around the foundation's mkNixosService helper.
# See darwin-server.nix for the macOS/launchd equivalent.
#
# Minimal usage (defaults to Unix domain socket):
#
#   inputs.ezpz-dndz.nixosModules.server
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
# To reference the socket from a reverse proxy (e.g. nginx):
#
#   locations."/".proxyPass =
#     "http://unix:${config.services.ezpz-dndz-server.socket}";
#
# Note: when using socket mode the reverse proxy user must be a member
# of the service group (cfg.group) so it can connect to the socket.
{
  self,
  foundation,
}:
foundation.lib.mkNixosService {
  name = "ezpz-dndz-server";
  inherit self;
}
