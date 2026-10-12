# programs.secret-prompt: installs the panel, asudo and with-secret, and writes
# ~/.config/secret-prompt/config from the options below.
self: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.secret-prompt;
  roles = ["background" "surface" "raised" "muted" "subtext" "command" "text" "accent" "error"];
  lines =
    lib.optional (cfg.theme != null) "theme = ${cfg.theme}"
    ++ lib.optional (cfg.appearance != null) "appearance = ${cfg.appearance}"
    ++ lib.optional (cfg.opacity != null) "opacity = ${toString cfg.opacity}"
    ++ lib.mapAttrsToList (role: hex: "${role} = ${hex}") cfg.colors;
in {
  options.programs.secret-prompt = {
    enable = lib.mkEnableOption "secret-prompt, asudo and with-secret";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "secret-prompt.packages.\${system}.default";
      description = "The secret-prompt package.";
    };

    theme = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [
        "system"
        "catppuccin-mocha"
        "catppuccin-macchiato"
        "catppuccin-frappe"
        "catppuccin-latte"
      ]);
      default = null;
      description = "The preset the colors start from; the panel's own default is catppuccin-mocha.";
    };

    appearance = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum ["dark" "light"]);
      default = null;
      description = "Overrides the preset's dark or light blur, for custom colors on the other side.";
    };

    opacity = lib.mkOption {
      type = lib.types.nullOr (lib.types.numbers.between 0 1);
      default = null;
      description = "How strongly the background color tints the blur.";
    };

    colors = lib.mkOption {
      type = lib.types.attrsOf (lib.types.strMatching "#?([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})");
      default = {};
      example = {
        accent = "#89B4FA";
        error = "#FAB387";
      };
      description = "Per-role overrides, #RRGGBB or #RRGGBBAA. Roles: ${lib.concatStringsSep ", " roles}.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (role: lib.elem role roles) (lib.attrNames cfg.colors);
        message = "programs.secret-prompt.colors: unknown role; the roles are ${lib.concatStringsSep ", " roles}";
      }
    ];
    home.packages = [cfg.package];
    xdg.configFile."secret-prompt/config" = lib.mkIf (lines != []) {
      text = lib.concatStringsSep "\n" lines + "\n";
    };
  };
}
