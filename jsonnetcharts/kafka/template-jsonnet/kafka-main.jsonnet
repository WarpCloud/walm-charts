// This expects to be run with `jsonnet -J <path to ksonnet-lib>`
local helm = import '../../../applib/helm.libsonnet';
local k = import '../../../applib/ksonnet-lib/ksonnet.beta.2/k.libsonnet';
local service = k.core.v1.service;
local servicePortType = service.mixin.spec.portsType;
local statefulSet = k.apps.v1beta1.statefulSet;
local deployment = k.extensions.v1beta1.deployment;

local kafka = import 'kafka.jsonnet';

// user-defined data
local default_config_str = importstr '../values.yaml';
local default_config = std.parseJson(default_config_str);

function(config={})

  local overall_config = std.mergePatch(default_config, config);
  local metaConfig = helm.transwarpMetaConfig(overall_config);
  local confd_config = std.mergePatch(
    std.mergePatch(kafka.common.configs.shared_kv(overall_config), overall_config.transwarpConfig),
    overall_config.advanceConfig
  );

  local configmapConf = {
    'kafka.toml': importstr 'files/kafka.toml',
    'jaas.conf.tmpl': importstr 'files/jaas.conf.tmpl',
    'consumer.properties.tmpl': importstr 'files/consumer.properties.tmpl',
    'producer.properties.tmpl': importstr 'files/producer.properties.tmpl',
    'server.properties.tmpl': importstr 'files/server.properties.tmpl',
    'kafka-env.sh.tmpl': importstr 'files/kafka-env.sh.tmpl',
    'tdh-env.sh.tmpl': importstr '../../../applib/transwarp-commonlib/6.0/files/tdh-env.sh.tmpl',
    'tdh-env.toml': importstr '../../../applib/transwarp-commonlib/6.0/files/tdh-env.toml',
    'kafka-confd.conf': std.manifestJsonEx(confd_config, '  '),
  };

  local configmap_md5 = std.md5(std.toString(configmapConf));
  {

    'kafka-entrypoint-configmap.json':
      helm.transwarpConfigmap(moduleName='kafka-entrypoint', name='', metaConfig=metaConfig, data={
        'entrypoint.sh': importstr 'files/entrypoint.sh',
      }),

    'kafka-confd-conf-configmap.json':
      helm.transwarpConfigmap(moduleName='kafka-confd-conf', name='', metaConfig=metaConfig, data=configmapConf),

    'kafka-statefulset.json':
      local moduleName = 'kafka';
      local extraEnv = [];

      helm.transwarpStatefulSet(moduleName=moduleName, name='', replicas=overall_config.appConfig.kafka.replicas, metaConfig=metaConfig) +
      helm.transwarpPodHardAntiAffinity(moduleName=moduleName, metaConfig=metaConfig) +
      kafka.kafka.kafkaPodSpecTemplate(_name=moduleName, metaConfig=metaConfig, overall_config=overall_config, extraEnv=extraEnv) +
      helm.transwarpTemplateAnnotations({'transwarp/configmap.md5': configmap_md5}),

      // local env = kafka.common.configs.shared_env(overall_config);
      // kafka.kafka.statefulset('kafka', overall_config { configmap_md5: configmap_md5 }, env),

    'kafka-svc.json':
      helm.transwarpNodeportService(
        moduleName='kafka', name='',
        ports=[
          servicePortType.newNamed('web', 9092, 9092),
        ],
        metaConfig=metaConfig
      ),

    'kafka-hl-svc.json':
      helm.transwarpHeadlessService(
        moduleName='kafka', name='',
        ports=[
          servicePortType.newNamed('web', 9092, 9092),
        ],
        metaConfig=metaConfig
      ),

  }
