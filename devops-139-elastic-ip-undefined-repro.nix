# usage:
#  nixops create -d devops-139-repro devops-139-elastic-ip-undefined-repro.nix
#  nixops modify -d devops-139-repro devops-139-elastic-ip-undefined-repro.nix && nixops deploy -d devops-139-repro

# output
# [nix-shell:~/devops-139]$ nixops modify -d devops-139-repro devops-139-elastic-ip-undefined-repro.nix && nixops deploy -d devops-139-repro
# repro-ip> creating elastic IP address (region ‘eu-central-1’)...
# repro-sg> creating EC2 security group ‘charon-636102ba-72b9-11e7-9c4e-06258a1e40fd-repro-sg’...
# repro-kp> uploading EC2 key pair ‘charon-636102ba-72b9-11e7-9c4e-06258a1e40fd-repro-kp’...
# repro-sg> adding new rules to EC2 security group ‘charon-636102ba-72b9-11e7-9c4e-06258a1e40fd-repro-sg’...
# repro-ip> IP address is 52.57.102.59
# error: EC2ResponseError: 400 Bad Request
# <?xml version="1.0" encoding="UTF-8"?>
# <Response><Errors><Error><Code>InvalidParameterValue</Code><Message>CIDR block _UNKNOWN_ELASTIC_IP_/32 is malformed</Message></Error></Errors><RequestID>2dc1621c-3037-4e87-abdd-1b8f12107cd2</RequestID></Response>

let
  hostPkgs = import <nixpkgs> {};
  lib = hostPkgs.lib;
in with lib; let
  accessKeyId = "repro-ak";  # NOTE: change this to, well, you know what
  region      = "eu-central-1";
in
{
  # deployment/cardano-nodes.nix
  # -> modules/cardano-node-config.nix
  network.description = "repro-depl";
  repro =
  { config, resources, pkgs, nodes, options, ... }: {
     deployment.targetEnv        = "ec2";
     deployment.ec2.accessKeyId  = accessKeyId;
     deployment.ec2.instanceType = mkDefault "t2.large";
     deployment.ec2.region       = region;
     deployment.ec2.keyPair      = resources.ec2KeyPairs.repro-kp;
     # deployment.ec2.ebsInitialRootDiskSize = mkDefault 30;

     networking.hostName = "repro-host";

     deployment.ec2.securityGroups = mkDefault [ resources.ec2SecurityGroups.repro-sg ];

     # deployment/cardano-node-env-dev.nix
     # -> modules/card-no-dev.nix
     #    -> common.nix
     #       -> cardano-node.nix
     deployment.ec2.elasticIPv4 = resources.elasticIPs.repro-ip;
  };
  resources = {
    ec2KeyPairs.repro-kp       = { inherit region accessKeyId; };
    elasticIPs.repro-ip        = { inherit region accessKeyId; };
    ec2SecurityGroups.repro-sg =
    { resources, ... }:
    let ip = resources.elasticIPs.repro-ip.address; # this evaluates to _UNKNOWN_ELASTIC_IP_
    in {
      inherit region accessKeyId;
      description = "repro-sg";
      rules = [{
        fromPort = 1;
        toPort   = 2;
        sourceIp = ip + "/32";
      }];
    };
  };
}
