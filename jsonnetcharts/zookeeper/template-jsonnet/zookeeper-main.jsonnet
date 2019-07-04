// This expects to be run with `jsonnet -J <path to ksonnet-lib>`
local helm = import '../../../applib/helm.libsonnet';
local k = import '../../../applib/ksonnet-lib/ksonnet.beta.2/k.libsonnet';
local service = k.core.v1.service;
local servicePortType = service.mixin.spec.portsType;
local statefulSet = k.apps.v1beta1.statefulSet;
local deployment = k.extensions.v1beta1.deployment;

local zookeeper = import './zookeeper.jsonnet';

// user-defined data
local default_config_str = importstr '../values.yaml';
local default_config = std.parseJson(default_config_str);

function(config={})

  local overall_config = std.mergePatch(default_config, config);
  local metaConfig = helm.transwarpMetaConfig(overall_config);
  local confd_config = std.mergePatch(
    std.mergePatch(zookeeper.common.configs.shared_kv(overall_config), overall_config.transwarpConfig),
    overall_config.advanceConfig
  );

  local configmapConf = {
    'zookeeper.toml': importstr 'files/zookeeper.toml',
    'zoo.cfg.tmpl': importstr 'files/zoo.cfg.tmpl',
    'jaas.conf.tmpl': importstr 'files/jaas.conf.tmpl',
    'zookeeper-env.sh.tmpl': importstr 'files/zookeeper-env.sh.tmpl',
    'myid.tmpl': importstr 'files/myid.tmpl',
    'log4j.properties.raw': importstr 'files/log4j.properties.raw',
    'tdh-env.sh.tmpl': importstr '../../../applib/transwarp-commonlib/6.0/files/tdh-env.sh.tmpl',
    'tdh-env.toml': importstr '../../../applib/transwarp-commonlib/6.0/files/tdh-env.toml',
    'zookeeper-confd.conf': std.manifestJsonEx(confd_config, '  '),
  };

  local configmap_md5 = std.md5(std.toString(configmapConf));
  {
    'zookeeper-entrypoint-configmap.json':
      helm.transwarpConfigmap(moduleName='zookeeper-entrypoint', name='', metaConfig=metaConfig, data={
        'entrypoint.sh': importstr 'files/entrypoint.sh',
      }),

    'zookeeper-confd-conf-configmap.json':
      helm.transwarpConfigmap(moduleName='zookeeper-confd-conf', name='', metaConfig=metaConfig, data=configmapConf),

    'zookeeper-statefulset.json':
      local moduleName = 'zookeeper';
      local extraEnv = [];

      helm.transwarpStatefulSet(moduleName=moduleName, name='', replicas=overall_config.appConfig.zookeeper.replicas, metaConfig=metaConfig) +
      helm.transwarpPodHardAntiAffinity(moduleName=moduleName, metaConfig=metaConfig) +
      zookeeper.zookeeper.zookeeperPodSpecTemplate(_name=moduleName, metaConfig=metaConfig, overall_config=overall_config, extraEnv=extraEnv),

    'zookeeper-hl-svc.json':
      helm.transwarpHeadlessService(
        moduleName='zookeeper', name='',
        ports=[
          servicePortType.newNamed('zk-port', overall_config.advanceConfig.zookeeper['zookeeper.client.port'], overall_config.advanceConfig.zookeeper['zookeeper.client.port']),
        ],
        metaConfig=metaConfig
      ),

    'release-config-crd.json':
      helm.transwarpReleaseConfig(moduleName='zookeeper', metaConfig=metaConfig, outputConfig={
        zookeeper_port: helm.commonlib.toString(overall_config.advanceConfig.zookeeper['zookeeper.client.port']),
        zookeeper_auth_type: "none",
        zookeeper_addresses: helm.commonlib.commbineStatefulSetService(
              helm.transwarpReleaseName('zookeeper', metaConfig), helm.transwarpNamespace(metaConfig),
              sep=',', replicas=overall_config.appConfig.zookeeper.replicas),
      }),

    // [ if overall_config.transwarpConfig.transwarpMetrics.enable then 'zookeeper-monitor-svc.json' ]:
    //   helm.transwarpHeadlessService(
    //     moduleName='zookeeper', name='zookeeper-metrics',
    //     ports=[
    //       servicePortType.newNamed('http-metrics', 19000, 19000),
    //     ],
    //     metaConfig=metaConfig
    //   ) + deployment.mixin.spec.template.metadata.labels({prometheus: "zookeeper"}),

    // [ if overall_config.transwarpConfig.transwarpMetrics.enable then 'zookeeper-monitor.json' ]:
    //   helm.transwarpServiceMonitor(moduleName='zookeeper', metaConfig=metaConfig, endpoints=[
    //     {
    //       bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
    //       port: 'http-metrics',
    //       scheme: 'http',
    //       interval: '15s',
    //     },
    //   ], metricsLabels={
    //     prometheus: "zookeeper",
    //   }),
  }
