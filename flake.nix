{
  description = "Voice typing for Linux with pre-recording buffer";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        pythonEnv = pkgs.python311.withPackages (ps: with ps; [
          numpy
          pyaudio
          webrtcvad
          torch
          pillow
          # Additional dependencies from requirements.txt
          pip
          virtualenv
          tkinter
        ]);

        voice-typing = pkgs.stdenv.mkDerivation rec {
          pname = "voice-typing-linux";
          version = "1.0.0";
          
          src = ./.;
          
          buildInputs = [
            pythonEnv
            pkgs.ffmpeg
            pkgs.sox
            pkgs.ydotool
            pkgs.xdotool
            pkgs.portaudio
            pkgs.scrot
            pkgs.xorg.libX11
            pkgs.xorg.libXext
            pkgs.xorg.libXinerama
            pkgs.gcc
            pkgs.pkg-config
            pkgs.stdenv.cc.cc.lib
            pkgs.zlib
          ];
          
          nativeBuildInputs = [ pkgs.makeWrapper ];
          
          installPhase = ''
            mkdir -p $out/bin $out/share/voice-typing
            
            # Copy the main script
            cp enhanced-voice-typing.py $out/share/voice-typing/
            chmod +x $out/share/voice-typing/enhanced-voice-typing.py
            
            # Create wrapper script
            makeWrapper ${pythonEnv}/bin/python $out/bin/voice-typing \
              --add-flags "$out/share/voice-typing/enhanced-voice-typing.py" \
              --prefix LD_LIBRARY_PATH : "${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.zlib}/lib" \
              --prefix PATH : "${pkgs.ffmpeg}/bin:${pkgs.sox}/bin:${pkgs.ydotool}/bin:${pkgs.xdotool}/bin:${pkgs.scrot}/bin" \
              --run 'export PYTHONPATH="${pythonEnv}/${pythonEnv.sitePackages}:$PYTHONPATH"' \
              --run 'pip install --user faster-whisper pyautogui python-xlib opencv-python-headless 2>/dev/null || true'
          '';
          
          meta = with pkgs.lib; {
            description = "Voice typing for Linux with pre-recording buffer";
            license = licenses.mit;
            platforms = platforms.linux;
            maintainers = [ ];
          };
        };

      in {
        packages = {
          default = voice-typing;
          voice-typing = voice-typing;
        };
        
        apps = {
          default = {
            type = "app";
            program = "${voice-typing}/bin/voice-typing";
          };
        };
      }
    ) // {
      nixosModules = {
        ydotool-service = { config, pkgs, lib, ... }: {
          options = {
            services.voice-typing.ydotool = {
              enable = lib.mkEnableOption "ydotool daemon for voice typing";
              user = lib.mkOption {
                type = lib.types.str;
                default = "root";
                description = "User to add to input group";
              };
            };
          };
          
          config = lib.mkIf config.services.voice-typing.ydotool.enable {
            # Create systemd service for ydotoold
            systemd.services.ydotoold = {
              description = "ydotool daemon";
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                ExecStart = "${pkgs.ydotool}/bin/ydotoold --socket-path=/run/ydotoold/socket --socket-perm=0666";
                Restart = "always";
                RuntimeDirectory = "ydotoold";
                RuntimeDirectoryMode = "0755";
                User = "root";
                Group = "root";
              };
            };

            # Add specified user to input group for device access
            users.users.${config.services.voice-typing.ydotool.user}.extraGroups = [ "input" ];
            
            # Create udev rule to make /dev/uinput accessible
            services.udev.extraRules = ''
              KERNEL=="uinput", MODE="0666"
            '';
            
            # Create a wrapper script that uses the system socket
            environment.systemPackages = [
              (pkgs.writeScriptBin "ydotool-client" ''
                #!${pkgs.bash}/bin/bash
                exec ${pkgs.ydotool}/bin/ydotool --socket-path=/run/ydotoold/socket "$@"
              '')
            ];
          };
        };
      };
    };
}