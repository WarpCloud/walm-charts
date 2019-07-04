local helm = import '../../../applib/helm.libsonnet';
local k = import '../../../applib/ksonnet-lib/ksonnet.beta.2/k.libsonnet';
local app = import '../../../applib/app.libsonnet';
local statefulSet = k.apps.v1beta1.statefulSet;
local deployment = k.extensions.v1beta1.deployment;
local templateSpecType = deployment.mixin.spec.template.specType;
local containersType = deployment.mixin.spec.template.spec.containersType;

{
  common:: {
    configs:: {
      shared_kv(config): {
        security: {
          'auth_type': 'none',
        },
      },
      shared_env(config): [],
    },

    configMap:: {
      volumeMounts(metaConfig):: [
        { name: 'zookeeper-entrypoint', mountPath: '/boot' },
        { name: 'zookeeper-confd-conf', mountPath: '/etc/confd' },
      ],
      volumes(metaConfig):: [
        {
          name: 'zookeeper-entrypoint',
          configMap: {
            name: helm.transwarpReleaseName('zookeeper-entrypoint', metaConfig),
            items: [
              { key: 'entrypoint.sh', path: 'entrypoint.sh', mode: 493 },
            ],
          },
        },
        {
          name: 'zookeeper-confd-conf',
          configMap: {
            name: helm.transwarpReleaseName('zookeeper-confd-conf', metaConfig),
            items: [
              { key: 'zookeeper.toml', path: 'conf.d/zookeeper.toml' },
              { key: 'tdh-env.toml', path: 'conf.d/tdh-env.toml' },
              { key: 'zookeeper-confd.conf', path: 'zookeeper-confd.conf' },
              { key: 'zoo.cfg.tmpl', path: 'templates/zoo.cfg.tmpl' },
              { key: 'jaas.conf.tmpl', path: 'templates/jaas.conf.tmpl' },
              { key: 'zookeeper-env.sh.tmpl', path: 'templates/zookeeper-env.sh.tmpl' },
              { key: 'myid.tmpl', path: 'templates/myid.tmpl' },
              { key: 'log4j.properties.raw', path: 'templates/log4j.properties.raw' },
              { key: 'tdh-env.sh.tmpl', path: 'templates/tdh-env.sh.tmpl' },
            ],
          },
        },
      ],
    },
  },

  zookeeper:: {
    zookeeperPodSpecTemplate(_name, metaConfig, overall_config, extraEnv)::
      local zkConfig = overall_config.appConfig.zookeeper;
      local env = zkConfig.env_list + $.common.configs.shared_env(overall_config) + extraEnv + [
          { 
            name: 'SERVICE_NAME', 
            value: helm.transwarpReleaseName(_name, metaConfig)
          },
          {
            name: 'SERVICE_NAMESPACE',
            value: helm.transwarpNamespace(metaConfig),
          },
          { 
            name: 'QUORUM_SIZE', 
            value: std.toString(zkConfig.replicas) 
          },
      ];
      local command = ['/boot/entrypoint.sh'];
      local resource = zkConfig.resources + {};
      local image = zkConfig.image;

      local zkContainer = helm.transwarpDefaultContainer(_name, image, command, env, resource) +
              containersType.volumeMounts(
                $.common.configMap.volumeMounts(metaConfig) + [
                  { name: 'zkdir', mountPath: '/var/transwarp' },
                ]
              ) + containersType.mixin.readinessProbe.mixinInstance({
                  exec: {
                    command: [
                      '/bin/bash',
                      '-c',
                      std.format('echo ruok|nc localhost %s > /dev/null && echo ok',
                                  overall_config.advanceConfig.zookeeper['zookeeper.client.port']),
                    ],
                  },
                  periodSeconds: 30,
                  initialDelaySeconds: 60,  
              });

      local volumes = $.common.configMap.volumes(metaConfig) + [];
      local volumeClaimTemplates = [
        helm.transwarpVolumeClaimTemplate(moduleName=_name, name='zkdir', metaConfig=metaConfig, storageConfig=zkConfig.resources.storage.data)
      ];

      helm.transwarpStatefulSetVolumeClaimTemplate(volumeClaimTemplates=volumeClaimTemplates) +
      helm.transwarpPodSpecTemplate(componentConfig=zkConfig, initContainers=[], containers=[zkContainer],volumes=volumes),
  },
    
}