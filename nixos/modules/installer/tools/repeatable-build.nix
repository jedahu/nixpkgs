{ config, pkgs, ... }:
with pkgs.lib;
with pkgs.lib.types;
{
  options = {
    system = {
      repeatableBuild = {
        enable = mkOption {
          type = bool;
          default = false;
          description = ''
            Whether to enable repeatable nixos-rebuilds or not. Repeatable
            builds use a git repo uri and refid to ensure that the system is
            built from a specific and stable nixpkgs collection.
          '';
        };
        uri = mkOption {
          type = uniq string;
          example = "NixOS/nixpkgs";
          description = ''
            The nixpkgs repository URI to pull from when running nixos-rebuild.
            Required for repeatable nixos-rebuild.

            Supported URIs:

            - /local/repo path
            - user/repo github shorthand
            - ssh:// and git:// remote schemes
                (for hosts that support git-archive (not github))

            URIs that are not github shorthand and not ssh:// or git:// are
            assumed to be local paths.
          '';
        };
        refid = mkOption {
          type = uniq string;
          example = "61befa04511551e3bdcb8150553e5c87bcd5abe3";
          description = ''
            The git tag or commit-id to use. Required for repeatable
            nixos-rebuild. Use one of the following combinations of uri and
            refid:

            - /local/repo with tag or commit-id
            - user/repo (github) with tag or commit-id
            - ssh:// or git:// uri with tag
                (git-archive on remote repos does not support commit-id)

            Don't use a branch name. Branch contents change over time but tag
            and commit-ids do not.
          '';
        };
        binaryCache = mkOption {
          type = string;
          default = "";
          example = "http://cache.nixos.org";
          description = ''
            A binary cache URI to go with the nixpkgs repo.
          '';
        };
      };
    };
  };
}
