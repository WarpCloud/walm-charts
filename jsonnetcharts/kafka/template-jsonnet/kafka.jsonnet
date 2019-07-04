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
        zookeeper_client_config: config.ZOOKEEPER_CLIENT_CONFIG,
        java_opts: {
          memory_opts: {
            // kafka_memory: std.toString(std.floor(config.appConfig.kafka.resources.memory_limit * 819)),
            kafka_memory: std.toString(std.floor(4 * 819)),
          },
        },
        server_properties: {
          'log.segment.bytes': 1073741824,
          'log.retention.bytes': std.floor(app.diskSizeInByte(config.appConfig.kafka.resources.storage.data.size) * 0.1),
        },
        security: {
          'auth_type': 'none',
        },
      },
      shared_env(config): [],
    },
    configMap:: {
      volumeMounts(config):: [
        { name: 'kafka-entrypoint', mountPath: '/boot' },
        { name: 'kafka-confd-conf', mountPath: '/etc/confd' },
      ],

      volumes(metaConfig):: [
        {
          name: 'kafka-entrypoint',
          configMap: {
            name: helm.transwarpReleaseName('kafka-entrypoint', metaConfig),
            items: [
              { key: 'entrypoint.sh', path: 'entrypoint.sh', mode: 493 },
            ],
          },
        },
        {
          name: 'kafka-confd-conf',
          configMap: {
            name: helm.transwarpReleaseName('kafka-confd-conf', metaConfig),
            items: [
              { key: 'kafka-confd.conf', path: 'kafka-confd.conf' },
              { key: 'kafka.toml', path: 'conf.d/kafka.toml' },
              { key: 'tdh-env.toml', path: 'conf.d/tdh-env.toml' },
              { key: 'jaas.conf.tmpl', path: 'templates/jaas.conf.tmpl' },
              { key: 'kafka-env.sh.tmpl', path: 'templates/kafka-env.sh.tmpl' },
              { key: 'server.properties.tmpl', path: 'templates/server.properties.tmpl' },
              { key: 'producer.properties.tmpl', path: 'templates/producer.properties.tmpl' },
              { key: 'consumer.properties.tmpl', path: 'templates/consumer.properties.tmpl' },
              { key: 'tdh-env.sh.tmpl', path: 'templates/tdh-env.sh.tmpl' },
            ],
          },
        },
      ],
    },
  },
  kafka:: {
    kafkaPodSpecTemplate(_name, metaConfig, overall_config, extraEnv)::
      local kafkaConfig = overall_config.appConfig.kafka;
      local env = kafkaConfig.env_list + extraEnv + [];
      local command = ['/boot/entrypoint.sh'];
      local resource = kafkaConfig.resources + {};
      local image = kafkaConfig.image;

      local kafkaContainer = helm.transwarpDefaultContainer(_name, image, command, env, resource) +
              containersType.volumeMounts(
                $.common.configMap.volumeMounts(metaConfig) + [
                  { name: 'data', mountPath: '/data' },
                  { name: 'log', mountPath: '/var/log/kafka' },
                ]
              );

      local volumes = $.common.configMap.volumes(metaConfig) + [
        helm.transwarpTosTmpDisk('log', kafkaConfig.resources.storage.log),
      ];
      local volumeClaimTemplates = [
        helm.transwarpVolumeClaimTemplate(moduleName=_name, name='data', metaConfig=metaConfig, storageConfig=kafkaConfig.resources.storage.data)
      ];

      helm.transwarpStatefulSetVolumeClaimTemplate(volumeClaimTemplates=volumeClaimTemplates) +
      helm.transwarpPodSpecTemplate(componentConfig=kafkaConfig, initContainers=[], containers=[kafkaContainer],volumes=volumes)
  },

}
