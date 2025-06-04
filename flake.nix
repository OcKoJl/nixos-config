{
  description = "Optimized NixOS configuration for AMD Ryzen + Radeon";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";  # LTS channel
    hardware.url = "github:NixOS/nixos-hardware";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, hardware, disko, ... }@inputs: {
    nixosConfigurations.amd-nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        # Disko disk configuration
        disko.nixosModules.disko
        ({ config, pkgs, ... }: {
          disko.devices = {
            disk.nvme0 = {
              type = "disk";
              device = "/dev/nvme0n1";
              content = {
                type = "gpt";
                partitions = {
                  boot = {
                    size = "512M";
                    type = "EF00";
                    content = {
                      type = "filesystem";
                      format = "vfat";
                      mountpoint = "/boot";
                    };
                  };
                  swap = {
                    size = "8G";
                    type = "8200";
                    content = {
                      type = "swap";
                      resumeDevice = true;
                    };
                  };
                  root = {
                    size = "100%";
                    content = {
                      type = "btrfs";
                      extraArgs = ["-f"];
                      subvolumes = {
                        "@" = {
                          mountpoint = "/";
                          mountOptions = [
                            "noatime"
                            "compress=zstd"
                            "ssd"
                            "discard=async"
                            "space_cache=v2"
                          ];
                        };
                        "@nix" = {
                          mountpoint = "/nix";
                          mountOptions = [
                            "nodatacow"
                            "nodatasum"
                            "noatime"
                          ];
                        };
                        "@home" = {
                          mountpoint = "/home";
                          mountOptions = [
                            "compress=zstd"
                            "noatime"
                          ];
                        };
                        "@log" = {
                          mountpoint = "/var/log";
                          mountOptions = [
                            "nodatacow"
                            "nodatasum"
                          ];
                        };
                        "@tmp" = {
                          mountpoint = "/tmp";
                          mountOptions = [
                            "nodatacow"
                            "nodatasum"
                            "noatime"
                          ];
                        };
                        "@snapshots" = {
                          mountpoint = "/.snapshots";
                        };
                      };
                    };
                  };
                };
              };
            };
          };
        })

        # Main configuration
        ({ config, pkgs, ... }: {
          # ===== Core System =====
          boot = {
            loader.systemd-boot.enable = true;
            kernelPackages = pkgs.linuxPackages_latest;
            kernelModules = [ "amdgpu" "kvm-amd" ];
            extraModprobeConfig = ''
              options amdgpu power_dpm_state=performance
            '';
            kernelParams = [
              "amd_pstate=active"
              "resume=/dev/disk/by-partuuid/${config.disko.devices.disk.nvme0.partitions.swap.content.partuuid}"
            ];
            supportedFilesystems = ["btrfs"];
          };

          networking.hostName = "amd-nixos";
          time.timeZone = "Your/Timezone";

          # ===== Swap & Memory =====
          swapDevices = [ {
            device = "/dev/disk/by-partuuid/${config.disko.devices.disk.nvme0.partitions.swap.content.partuuid}";
            priority = 0;
            discardPolicy = "both";
          } ];

          zramSwap = {
            enable = true;
            algorithm = "zstd";
            memoryPercent = 125;
            priority = 100;
          };

          services.btrfs.autoScrub = {
            enable = true;
            interval = "weekly";
            fileSystems = [ "/" ];
          };

          # ===== AMD GPU =====
          hardware.opengl = {
            enable = true;
            driSupport = true;
            driSupport32Bit = true;
            extraPackages = with pkgs; [
              rocm-opencl-icd
              amdvlk
            ];
            extraPackages32 = with pkgs; [
              driversi686Linux.amdvlk
            ];
          };

          # ===== Power Management =====
          powerManagement.cpuFreqGovernor = "performance";
          services.thermald.enable = true;

          # ===== User Config =====
          users.users.youruser = {
            isNormalUser = true;
            extraGroups = [ "wheel" "video" "networkmanager" "libvirtd" ];
            packages = with pkgs; [
              neovim git htop
              radeontop # GPU monitoring
            ];
          };

          # ===== System Packages =====
          environment.systemPackages = with pkgs; [
            smartmontools # SSD health monitoring
            btrfs-progs
            pciutils
          ];

          # ===== Virtualization =====
          virtualisation.libvirtd.enable = true;
          boot.extraModprobeConfig = ''
            options kvm_amd nested=1
          '';

          system.stateVersion = "25.05";
        })

        # Hardware quirks
        hardware.nixosModules.common-cpu-amd
        hardware.nixosModules.common-gpu-amd
      ];
    };
  };
}
