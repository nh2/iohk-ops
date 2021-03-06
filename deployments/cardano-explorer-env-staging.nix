{ accessKeyId, ... }:

with (import ./../lib.nix);

{
  sl-explorer = { config, ... }: {
    imports = [ ./../modules/cardano-node-staging.nix ];

    deployment.route53 = {
      hostName = mkForce "cardano-explorer.aws.iohkdev.io";
    };
  };

  resources = {
    elasticIPs = {
      nodeip40 = { inherit region accessKeyId; };
    };
  };
}
