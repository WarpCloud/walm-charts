local k = import 'ksonnet-lib/ksonnet.beta.2/k.libsonnet';
local k8s = import 'ksonnet-lib/ksonnet.beta.2/k8s.libsonnet';

local deployment = k.extensions.v1beta1.deployment;
local statefulSet = k.apps.v1beta1.statefulSet;
local ingress = k.extensions.v1beta1.ingress;
local daemonSet = k.extensions.v1beta1.daemonSet;
local configMap = k.core.v1.configMap;
local job = k.batch.v1.job;
local service = k.core.v1.service;
local serviceAccount = k.core.v1.serviceAccount;
local role = k8s.rbac.v1beta1.role;
local roleBinding = k8s.rbac.v1beta1.roleBinding;
local roleRefType = k8s.rbac.v1beta1.roleBinding.mixin.roleRefType;
local roleSubjectsType = k8s.rbac.v1beta1.roleBinding.subjectsType;
local policyRule = k8s.rbac.v1beta1.role.rulesType;
local servicePortType = service.mixin.spec.portsType;
local templateSpecType = deployment.mixin.spec.template.specType;
local containersType = deployment.mixin.spec.template.spec.containersType;
local resourcesType = containersType.mixin.resourcesType;
{
  /* Common Lib Function */
  parseYaml:: std.native("parseYaml"),

  commonlib:: {
    commbineStatefulSetService(releaseName, releaseNamespace, sep=',', replicas=1)::
      std.join(
        sep, std.makeArray(replicas, function(i)
                std.join('.', [
                  releaseName + '-' + std.toString(i),
                  releaseName + '-hl',
                  releaseNamespace,
                  'svc',
                ])
            )
      ),

    toString(object)::
      if std.type(object) == 'number' then std.toString(object)
      else object,

  unitSizeInByte(size)::
    local isDigitOrPoint(ch) = (std.codepoint(ch) >= 48 && std.codepoint(ch) <=57) || std.codepoint(ch) == 46;
    local digits(ch) = if isDigitOrPoint(ch) then ch else "";
    local unit(ch) = if isDigitOrPoint(ch) then "" else ch;

    local _size = self.parseNumber(std.join("", std.map(digits, size)));
    local _unit = std.join("", std.map(unit, size));
    local toPower(unit) =
        if std.startsWith(unit, "G") || std.startsWith(unit, "g")
            then 1024 * 1024 * 1024
        else if std.startsWith(unit, "M") || std.startsWith(unit, "m")
            then 1024 * 1024
        else if std.startsWith(unit, "K") || std.startsWith(unit, "k")
            then 1024
        else if std.startsWith(unit, "B") || std.startsWith(unit, "b")
            then 1
        else 1;
    std.floor(_size * toPower(_unit)),

    convertPriorityClassName(priority=0)::
      if priority < 100 then 'low-priority'
      else if priority < 150 then 'medium-priority'
      else if priority < 200 then 'high-priority'
      else 'system-priority',

    containerResourcesV2(config):: {
      local _cpu_request = if std.objectHas(config, 'cpu_request') then config.cpu_request else 0,
      local _cpu_limit = if std.objectHas(config, 'cpu_limit') then config.cpu_limit else 0,
      local _memory_request = if std.objectHas(config, 'memory_request') then config.memory_request else 0,
      local _memory_limit = if std.objectHas(config, 'memory_limit') then config.memory_limit else 0,
      local _gpu_request = if std.objectHas(config, 'gpu_request') then config.gpu_request else 0,
      local _gpu_limit = if std.objectHas(config, 'gpu_limit') then config.gpu_limit else 0,
      limits: {
        'memory': std.toString(_memory_limit),
        'cpu': std.toString(_cpu_limit),
        'nvidia.com/gpu': std.toString(_gpu_limit),
      },
      requests: {
        'memory': std.toString(_memory_request),
        'cpu': std.toString(_cpu_request),
        'nvidia.com/gpu': std.toString(_gpu_request),
      },
    },
  },
  /* End */

  // TOS 特殊资源
  cniNetwork(config={})::
    if std.objectHas(config, 'Transwarp_Cni_Network') && std.length(config.Transwarp_Cni_Network) > 0 then
      config.Transwarp_Cni_Network
    else 'overlay',

  transwarpTosTmpDisk(name, storageConfig):: {
    name: name,
    tosDisk: {
      name: name,
      storageType: storageConfig.storageClass,
      capability: storageConfig.size,
      accessMode: storageConfig.accessMode,
    },
  },

  transwarpEmptyDir(name):: {
    name: name,
    emptyDir: {},
  },

  transwarpHostShareDirVolume(metaConfig):: {
    socketDir:
      deployment.mixin.spec.template.spec.volumesType.fromHostPath('socketdir', '/tmp/transwarp-hostsharedir/' + $.transwarpNamespace(metaConfig) + '/root/docker/common'),
  },

  transwarpTosFlannelLocality(config):: {
    flannelVolumeMounts:
      containersType.volumeMounts(
        deployment.mixin.spec.template.spec.containers.volumeMountsType.new('flanneldir', '/var/run/hadoop-flannel')
      ),
    flannelVolumes:
      deployment.mixin.spec.template.spec.volumesType.fromHostPath('flanneldir', '/var/run/hadoop-flannel/' + $.cniNetwork(config)),
  },

  transwarp:: {
    v1beta1:: {
      local apiVersion = { apiVersion: 'apiextensions.transwarp.io/v1beta1' },

      releaseConfig:: {
        local kind = { kind: 'ReleaseConfig' },
        new():: apiVersion + kind,
        mixin:: {
          metadata:: {
            local __metadataMixin(metadata) = { metadata+: metadata },
            mixinInstance(metadata):: __metadataMixin(metadata),
            annotations(annotations):: __metadataMixin({ annotations+: annotations }),
            labels(labels):: __metadataMixin({ labels+: labels }),
            name(name):: __metadataMixin({ name: name }),
            namespace(namespace):: __metadataMixin({ namespace: namespace }),
          },
          spec:: {
            local __specMixin(spec) = { spec+: spec },
            mixinInstance(spec):: __specMixin(spec),
            outputConfig:: {
              local __outputConfigMixin(outputConfig) = __specMixin({ outputConfig+: outputConfig }),
              mixinInstance(outputConfig):: __outputConfigMixin(outputConfig),
            },
            chartName(chartName):: __specMixin({ chartName: chartName }),
            chartVersion(chartVersion):: __specMixin({ chartVersion: chartVersion }),
            chartAppVersion(chartAppVersion):: __specMixin({ chartAppVersion: chartAppVersion }),
          },
        },
      },
    },
  },

  servicemonitor:: {
    v1:: {
      local apiVersion = { apiVersion: 'monitoring.coreos.com/v1' },

      serviceMonitor:: {
        local kind = { kind: 'ServiceMonitor' },
        new():: apiVersion + kind,
        mixin:: {
          metadata:: {
            local __metadataMixin(metadata) = { metadata+: metadata },
            mixinInstance(metadata):: __metadataMixin(metadata),
            annotations(annotations):: __metadataMixin({ annotations+: annotations }),
            labels(labels):: __metadataMixin({ labels+: labels }),
            name(name):: __metadataMixin({ name: name }),
            namespace(namespace):: __metadataMixin({ namespace: namespace }),
          },
          spec:: {
            local __specMixin(spec) = { spec+: spec },
            mixinInstance(spec):: __specMixin(spec),
            jobLabel(jobLabel):: __specMixin({ jobLabel: jobLabel }),
            labelSelector:: {
              local __labelSelectorMixin(labelSelector) = __specMixin({ labelSelector+: labelSelector }),
              mixinInstance(labelSelector):: __labelSelectorMixin(labelSelector),
            },
            namespaceSelector:: {
              local __namespaceSelectorMixin(namespaceSelector) = __specMixin({ namespaceSelector+: namespaceSelector }),
              mixinInstance(namespaceSelector):: __namespaceSelectorMixin(namespaceSelector),
            },
            endpoints:: {
              local __endpointsMixin(endpoints) = __specMixin({ endpoints+: endpoints }),
              mixinInstance(endpoints):: __endpointsMixin(endpoints),
            },
          },
        },
      },

      prometheusRule:: {
        local kind = { kind: 'PrometheusRule' },
        new():: apiVersion + kind,
        mixin:: {
          metadata:: {
            local __metadataMixin(metadata) = { metadata+: metadata },
            mixinInstance(metadata):: __metadataMixin(metadata),
            annotations(annotations):: __metadataMixin({ annotations+: annotations }),
            labels(labels):: __metadataMixin({ labels+: labels }),
            name(name):: __metadataMixin({ name: name }),
            namespace(namespace):: __metadataMixin({ namespace: namespace }),
          },
          spec:: {
            local __specMixin(spec) = { spec+: spec },
            mixinInstance(spec):: __specMixin(spec),
            groups:: {
              local __groupsMixin(groups) = __specMixin({ groups+: groups }),
              mixinInstance(groups):: __groupsMixin(groups),
            },
          },
        },
      },

    },
  },

  transwarpMetaConfig(config):: {
    'helmReleaseName': if std.objectHas(config, 'helmReleaseName') then config.helmReleaseName else "",
    'helmReleaseNamespace': if std.objectHas(config, 'helmReleaseNamespace') then config.helmReleaseNamespace else "",
    'chartVersion': if std.objectHas(config, 'chartVersion') then config.chartVersion else "",
    'chartName': if std.objectHas(config, 'chartName') then config.chartName else "",
    'chartAppVersion': if std.objectHas(config, 'chartAppVersion') then config.chartAppVersion else "",

    'Transwarp_Install_Namespace': if std.objectHas(config, 'Transwarp_Install_Namespace') then config.Transwarp_Install_Namespace else "",
    'Transwarp_Install_ID': if std.objectHas(config, 'Transwarp_Install_ID') then config.Transwarp_Install_ID else "",
  },

  transwarpNamespace(metaConfig)::
    if std.objectHas(metaConfig, 'Transwarp_Install_Namespace') &&
      std.length(metaConfig.Transwarp_Install_Namespace) > 0 then metaConfig.Transwarp_Install_Namespace
    else if std.objectHas(metaConfig, 'helmReleaseNamespace') &&
      std.length(metaConfig.helmReleaseNamespace) > 0 then metaConfig.helmReleaseNamespace
    else
      'default',

  transwarpReleaseName(moduleName, metaConfig)::
    if std.objectHas(metaConfig, 'fullnameOverride') then
      metaConfig.fullnameOverride
    else
      metaConfig.helmReleaseName + '-' + moduleName,

  transwarpObjectLabels(moduleName, metaConfig):: {
    'app.kubernetes.io/name': moduleName,
    'app.kubernetes.io/instance': metaConfig.helmReleaseName,
    'app.kubernetes.io/version': metaConfig.chartAppVersion,
    'app.kubernetes.io/component': metaConfig.chartName,
    'app.kubernetes.io/part-of': metaConfig.chartName,
    'app.kubernetes.io/managed-by': 'walm',
  },

  transwarpObjectTemplateLabels(moduleName, metaConfig):: {
    'app.kubernetes.io/name': moduleName,
    'app.kubernetes.io/instance': metaConfig.helmReleaseName,
    'app.kubernetes.io/version': metaConfig.chartAppVersion,
  },

  transwarpObjectTemplateSelector(moduleName, metaConfig):: {
    'app.kubernetes.io/name': moduleName,
    'app.kubernetes.io/instance': metaConfig.helmReleaseName,
    'app.kubernetes.io/version': metaConfig.chartAppVersion,
  },

  transwarpConvertPriorityClassName(priority=0)::
    if priority < 100 then 'low-priority'
    else if priority < 150 then 'medium-priority'
    else if priority < 200 then 'high-priority'
    else 'transwarp-priority',

  transwarpResources(config)::
    local _cpu_request = if std.objectHas(config, 'cpu_request') then config.cpu_request else 0;
    local _cpu_limit = if std.objectHas(config, 'cpu_limit') then config.cpu_limit else 0;
    local _memory_request = if std.objectHas(config, 'memory_request') then config.memory_request else 0;
    local _memory_limit = if std.objectHas(config, 'memory_limit') then config.memory_limit else 0;
    local _gpu_request = if std.objectHas(config, 'gpu_request') then config.gpu_request else 0;
    local _gpu_limit = if std.objectHas(config, 'gpu_limit') then config.gpu_limit else 0;
    resourcesType.new().limits({
      'memory': std.toString(_memory_limit),
      [if std.parseInt(_cpu_limit) > 0 then 'cpu']: std.toString(_cpu_limit),
      [if std.parseInt(_gpu_limit) > 0 then 'nvidia.com/gpu']: std.toString(_gpu_limit),
    }).requests({
      'memory': std.toString(_memory_request),
      [if std.parseInt(_cpu_request) > 0 then 'cpu']: std.toString(_cpu_request),
      [if std.parseInt(_gpu_request) > 0 then 'nvidia.com/gpu']: std.toString(_gpu_request),
    }),

  transwarpContainerResourcesEnvironment(containerName)::
    [
      {
        name: 'TOS_CPU_REQUEST',
        valueFrom: {
          resourceFieldRef: {
            containerName: containerName,
            resource: 'requests.cpu',
          },
        },
      },
      {
        name: 'TOS_CPU_LIMIT',
        valueFrom: {
          resourceFieldRef: {
            containerName: containerName,
            resource: 'limits.cpu',
          },
        },
      },
      {
        name: 'TOS_MEM_REQUEST',
        valueFrom: {
          resourceFieldRef: {
            containerName: containerName,
            resource: 'requests.memory',
          },
        },
      },
      {
        name: 'TOS_MEM_LIMIT',
        valueFrom: {
          resourceFieldRef: {
            containerName: containerName,
            resource: 'limits.memory',
          },
        },
      },
    ],

  transwarpObjectAnnotations(moduleName='', metaConfig={}):: {
  },

  transwarpTemplateAnnotations(annotations={})::
    deployment.mixin.spec.template.metadata.annotations(annotations),

  // Affinity函数定义
  transwarpPodHardAffinity(moduleName='', metaConfig={})::
    local affinityType =
      deployment.mixin.spec.template.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecutionType;
    deployment.mixin.spec.template.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecution(
      affinityType.new() + affinityType.namespaces($.transwarpNamespace(metaConfig)) +
      affinityType.topologyKey('kubernetes.io/hostname') +
      affinityType.mixin.labelSelector.matchLabels($.transwarpObjectTemplateSelector(moduleName, metaConfig))
    ),

  transwarpPodSoftAffinity(moduleName='', metaConfig={}, weight=100)::
    local affinityType =
      deployment.mixin.spec.template.spec.affinity.podAffinity.preferredDuringSchedulingIgnoredDuringExecutionType;
    deployment.mixin.spec.template.spec.affinity.podAffinity.preferredDuringSchedulingIgnoredDuringExecution(
      affinityType.new() + affinityType.weight(weight) + affinityType.mixin.podAffinityTerm.namespaces($.transwarpNamespace(metaConfig)) +
      affinityType.mixin.podAffinityTerm.topologyKey('kubernetes.io/hostname') +
      affinityType.mixin.podAffinityTerm.labelSelector.matchLabels($.transwarpObjectTemplateSelector(moduleName, metaConfig))
    ),

  transwarpPodHardAntiAffinity(moduleName='', metaConfig={})::
    local affinityType =
      deployment.mixin.spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecutionType;
    deployment.mixin.spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution(
      affinityType.new() + affinityType.namespaces($.transwarpNamespace(metaConfig)) +
      affinityType.topologyKey('kubernetes.io/hostname') +
      affinityType.mixin.labelSelector.matchLabels($.transwarpObjectTemplateSelector(moduleName, metaConfig))
    ),

  transwarpPodSoftAntiAffinity(moduleName='', metaConfig={}, weight=100)::
    local affinityType =
      deployment.mixin.spec.template.spec.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecutionType;
    deployment.mixin.spec.template.spec.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution(
      affinityType.new() + affinityType.weight(weight) + affinityType.mixin.podAffinityTerm.namespaces($.transwarpNamespace(metaConfig)) +
      affinityType.mixin.podAffinityTerm.topologyKey('kubernetes.io/hostname') +
      affinityType.mixin.podAffinityTerm.labelSelector.matchLabels($.transwarpObjectTemplateSelector(moduleName, metaConfig)),
    ),

  transwarpNodeAffinity(nodeTermsConfig={})::
    local nodeTermsType =
      deployment.mixin.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecutionType.nodeSelectorTermsType;
    deployment.mixin.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms(
      nodeTermsType.new() + nodeTermsType.matchExpressions(nodeTermsConfig)
    ),

  // Kubernetes Service类型函数定义
  transwarpNodeportService(moduleName='', name='', ports=[servicePortType.newNamed('unamed', 5000, 5000)], metaConfig={})::
    local _fixModuleName = if std.length(name) > 0 then name else moduleName;
    local _name = $.transwarpReleaseName(_fixModuleName, metaConfig);
    service.new(_name, self.transwarpObjectTemplateSelector(moduleName, metaConfig), ports) +
    service.mixin.metadata.annotations($.transwarpObjectAnnotations(moduleName, metaConfig)) +
    service.mixin.metadata.labels($.transwarpObjectLabels(moduleName, metaConfig) + {
      'app.kubernetes.io/service-type': 'nodeport-service',
    }) + 
    service.mixin.spec.type('NodePort'),

  transwarpHeadlessService(moduleName='', name='', ports=[servicePortType.newNamed('unamed', 5000, 5000)], metaConfig={})::
    local _fixModuleName = if std.length(name) > 0 then name else moduleName + '-hl';
    local _name = $.transwarpReleaseName(_fixModuleName, metaConfig);
    service.new(_name, $.transwarpObjectTemplateSelector(moduleName, metaConfig), ports) +
    service.mixin.metadata.annotations(
      { 'service.alpha.kubernetes.io/tolerate-unready-endpoints': 'true' }
    ) +
    service.mixin.metadata.labels($.transwarpObjectLabels(moduleName, metaConfig) + {
      'app.kubernetes.io/service-type': 'headless-service',
    }) +
    service.mixin.metadata.annotations($.transwarpObjectAnnotations(moduleName, metaConfig)) +
    service.mixin.spec.clusterIp('None'),

  // Kubernetes Ingress函数定义
  transwarpBaseIngress(moduleName='', name='', metaConfig={})::
    local _fixModuleName = if std.length(name) > 0 then name else moduleName;
    local _name = $.transwarpReleaseName(_fixModuleName, metaConfig);
    ingress.new().name(_name) +
    ingress.mixin.metadata.labels($.transwarpObjectLabels(moduleName, metaConfig)) +
    ingress.mixin.metadata.annotations($.transwarpObjectAnnotations(moduleName, metaConfig)),

  transwarpSubPathIngress(moduleName='', name='', metaConfig={}, subPath='', servicePort=5000, enableHttps=true)::
    local _fixServiceModuleName = if std.length(name) > 0 then name else moduleName + '-hl';
    local _serviceName = $.transwarpReleaseName(_fixServiceModuleName, metaConfig);
    local rulesType = ingress.mixin.spec.rulesType;
    $.transwarpBaseIngress(moduleName, name, metaConfig) +
    ingress.mixin.metadata.annotations({
      'kubernetes.io/ingress.class': 'nginx',
      'nginx.ingress.kubernetes.io/proxy-body-size': '1024m',
      'nginx.ingress.kubernetes.io/affinity': 'cookie',
      'nginx.ingress.kubernetes.io/use-port-in-redirects': 'true',
      'nginx.ingress.kubernetes.io/enable-strip-uri': 'true',

      'nginx.ingress.kubernetes.io/rewrite-target': '/',
      'nginx.ingress.kubernetes.io/redirect-by-referer': 'true',
      'nginx.ingress.kubernetes.io/proxy-redirect-from': '$scheme://$host:$server_port/',
      'nginx.ingress.kubernetes.io/proxy-redirect-to': subPath + '/',
      'nginx.ingress.kubernetes.io/proxy-cookie-path': '/ ' + subPath + '/',
    }) +
    if enableHttps then ingress.mixin.metadata.annotations({
      'nginx.ingress.kubernetes.io/secure-backends': 'true'
    }) +
    ingress.mixin.spec.rules(rulesType.new().mixin.http.paths({
      path: subPath,
      backend: {
        serviceName: _serviceName,
        servicePort: servicePort,
      },
    })),

  transwarpTosCasSubPathIngress(moduleName='', name='', metaConfig={}, subPath='', servicePort=5000, enableHttps=true, namespace='')::
    local _fixServiceModuleName = if std.length(name) > 0 then name else moduleName + '-hl';
    local _serviceName = $.transwarpReleaseName(_fixServiceModuleName, metaConfig);
    $.transwarpSubPathIngress(moduleName, name, metaConfig, subPath, servicePort, enableHttps) +
    ingress.mixin.metadata.annotations({
      'nginx.ingress.kubernetes.io/redirect-by-service-domain': 'true',
      'nginx.ingress.kubernetes.io/upstream-vhost': _serviceName + '.' + namespace + '.svc:' + std.toString(servicePort),
      'nginx.ingress.kubernetes.io/upstream-forwarded-host': _serviceName + '.' + namespace + '.svc:' + std.toString(servicePort),
    }),

  // Kubernetes PodTemplate函数定义
  /* 内置tosAppConfig解析 */
  transwarpTosAppSettings(tosAppConfig={})::
    (if std.objectHas(tosAppConfig, 'use_host_network')
     then deployment.mixin.spec.template.spec.withHostNetwork(tosAppConfig.use_host_network)
     else {}) + (if std.objectHas(tosAppConfig, 'priority')
                 then deployment.mixin.spec.template.spec.withPriorityClassName($.ConvertPriorityClassName(tosAppConfig.priority))
                 else {}),

  transwarpTosAutoInjectedVolume(config)::
    local auto_Injected_Volumes = if std.objectHas(config, 'Transwarp_Config') && std.objectHas(config.Transwarp_Config, 'Transwarp_Auto_Injected_Volumes') &&
                                     std.length(config.Transwarp_Config.Transwarp_Auto_Injected_Volumes) > 0 then true else false;
    {
      autoInjectedContainer: if auto_Injected_Volumes then
        deployment.mixin.spec.template.spec.containersType.volumeMounts([
          deployment.mixin.spec.template.spec.container.volumeMountsType.new(item.volumeName, '/var/run/secrets/transwarp.io/tosvolume/' + item.volumeName)
          for item in config.Transwarp_Config.Transwarp_Auto_Injected_Volumes
        ])
      else {},
      autoInjectedVolumes: if auto_Injected_Volumes then [
        deployment.mixin.spec.template.spec.volumesType.fromSecret(item.volumeName, item.secretname)
        for item in config.Transwarp_Config.Transwarp_Auto_Injected_Volumes
      ] else [],
    },

  transwarpPodTemplate(moduleName='', name='', appConfig={})::
    deployment.mixin.spec.template.spec.volumes(
      $.transwarpTosAutoInjectedVolume(appConfig).autoInjectedVolumes
    ),
    // deployment.mixin.spec.template.spec.hostNetwork(),
    // priorityClassName ,
    // k.apps.v1beta1.statefulSet.mixin.spec.template.spec.withVolumesMixin($.transwarpTosAutoInjectedVolume(config).autoInjectedVolumes)

  // Kubernetes StatefulSet函数定义
  transwarpVolumeClaimTemplate(moduleName='', name='', metaConfig={}, storageConfig={})::
    local persistentVolumeClaim = k.core.v1.persistentVolumeClaim;
    persistentVolumeClaim.mixin.metadata.name(name) +
    persistentVolumeClaim.mixin.metadata.annotations({
      'volume.beta.kubernetes.io/storage-class': storageConfig.storageClass,
    }) +
    persistentVolumeClaim.mixin.metadata.annotations($.transwarpObjectAnnotations(moduleName, metaConfig)) +
    persistentVolumeClaim.mixin.metadata.labels($.transwarpObjectLabels(moduleName, metaConfig)) +
    persistentVolumeClaim.mixin.spec.storageClassName(storageConfig.storageClass) +
    persistentVolumeClaim.mixin.spec.accessModes(storageConfig.accessMode) +
    persistentVolumeClaim.mixin.spec.resources.requests({ storage: storageConfig.size }) +
    if std.objectHas(storageConfig, 'limits') && std.length(storageConfig.limits) > 0 then 
      persistentVolumeClaim.mixin.spec.resources.limits(storageConfig.limits) else {},

  transwarpStatefulSetVolumeClaimTemplate(volumeClaimTemplates=[])::
    statefulSet.mixin.spec.volumeClaimTemplates(volumeClaimTemplates),

  transwarpStatefulSet(moduleName='', name='', replicas=0, metaConfig={})::
    local _fixModuleName = if std.length(name) > 0 then name else moduleName;
    local _name = $.transwarpReleaseName(_fixModuleName, metaConfig);
    local _fixServiceModuleName = if std.length(name) > 0 then name else moduleName + '-hl';
    local _serviceName = $.transwarpReleaseName(_fixServiceModuleName, metaConfig);
    // local _podTemplate = $.transwarpPodTemplate(moduleName, name, metaConfig, appConfig) + podTemplate;
    statefulSet.new() +
    statefulSet.mixin.metadata.name(_name) +
    statefulSet.mixin.metadata.annotations($.transwarpObjectAnnotations(moduleName, metaConfig)) +
    statefulSet.mixin.metadata.labels($.transwarpObjectLabels(moduleName, metaConfig)) +
    statefulSet.mixin.spec.podManagementPolicy('Parallel') +
    statefulSet.mixin.spec.replicas(replicas) +
    statefulSet.mixin.spec.serviceName(_serviceName) +
    statefulSet.mixin.spec.updateStrategy.type('RollingUpdate') +
    statefulSet.mixin.spec.selector.matchLabels($.transwarpObjectTemplateSelector(moduleName, metaConfig)) +
    statefulSet.mixin.spec.template.metadata.annotations({ 'tos.network.staticIP': 'true' }) +
    statefulSet.mixin.spec.template.metadata.labels($.transwarpObjectTemplateLabels(moduleName, metaConfig)) +
    statefulSet.mixin.spec.template.spec.restartPolicy('Always'),
    // statefulSet.mixin.spec.template.mixinInstance(_podTemplate),

  // Kubernetes Deployment函数定义
  transwarpDeployment(moduleName='', name='', replicas=0, metaConfig={})::
    local _fixModuleName = if std.length(name) > 0 then name else moduleName;
    local _name = $.transwarpReleaseName(_fixModuleName, metaConfig);
    // local _podTemplate = $.transwarpPodTemplate(moduleName, name, metaConfig, appConfig) + podTemplate;
    deployment.new(_name, replicas, [], {}) +
    deployment.mixin.metadata.annotations($.transwarpObjectAnnotations(moduleName, metaConfig)) +
    deployment.mixin.metadata.labels($.transwarpObjectLabels(moduleName, metaConfig)) +
    deployment.mixin.spec.strategy.type('RollingUpdate') +
    deployment.mixin.spec.selector.matchLabels($.transwarpObjectTemplateSelector(moduleName, metaConfig)) +
    deployment.mixin.spec.template.metadata.labels($.transwarpObjectTemplateLabels(moduleName, metaConfig)) +
    deployment.mixin.spec.template.spec.restartPolicy('Always'),
    // deployment.mixin.spec.template.mixinInstance(_podTemplate),

  // Kubernetes DaemonSet函数定义
  transwarpDaemonSet(moduleName='', name='', replicas=0, metaConfig={})::
    local _fixModuleName = if std.length(name) > 0 then name else moduleName;
    local _name = $.transwarpReleaseName(_fixModuleName, metaConfig);
    // local _podTemplate = $.transwarpPodTemplate(moduleName, name, metaConfig, appConfig) + podTemplate;
    daemonSet.new() +
    daemonSet.mixin.metadata.name(_name) +
    daemonSet.mixin.metadata.annotations($.transwarpObjectAnnotations(moduleName, metaConfig)) +
    daemonSet.mixin.metadata.labels($.transwarpObjectLabels(moduleName, metaConfig)) +
    daemonSet.mixin.spec.replicas(replicas) +
    daemonSet.mixin.spec.selector.matchLabels($.transwarpObjectTemplateSelector(moduleName, metaConfig)) +
    daemonSet.mixin.spec.template.metadata.labels($.transwarpObjectTemplateLabels(moduleName, metaConfig)) +
    daemonSet.mixin.spec.template.updateStrategy.type('RollingUpdate') +
    daemonSet.mixin.spec.template.spec.restartPolicy('Always'),

  // Kubernetes Job函数定义
  transwarpJob(moduleName='', name='', metaConfig={})::
    {},

  // Kubernetes Configmap函数定义
  transwarpConfigmap(moduleName='', name='', metaConfig={}, data={})::
    local _fixModuleName = if std.length(name) > 0 then name else moduleName;
    local _name = $.transwarpReleaseName(_fixModuleName, metaConfig);
    configMap.new() + configMap.data(data) +
    configMap.mixin.metadata.name(_name) +
    configMap.mixin.metadata.annotations($.transwarpObjectAnnotations(moduleName, metaConfig)) +
    configMap.mixin.metadata.labels($.transwarpObjectLabels(moduleName, metaConfig)),

  transwarpReleaseConfig(moduleName='', metaConfig=metaConfig, outputConfig={})::
    $.transwarp.v1beta1.releaseConfig.new() +
    $.transwarp.v1beta1.releaseConfig.mixin.metadata.name(metaConfig.helmReleaseName) +
    $.transwarp.v1beta1.releaseConfig.mixin.metadata.annotations($.transwarpObjectAnnotations(moduleName, metaConfig)) +
    $.transwarp.v1beta1.releaseConfig.mixin.metadata.labels($.transwarpObjectLabels(moduleName, metaConfig)) +
    $.transwarp.v1beta1.releaseConfig.mixin.spec.outputConfig.mixinInstance(outputConfig),

  transwarpDefaultContainer(_name='', image='', command=[], env=[], resources={})::

      local _containerResourceV2 = $.commonlib.containerResourcesV2(resources);
      containersType.new(_name, image) +
      containersType.command(command) +
      containersType.env(env) +
      containersType.imagePullPolicy('Always')+
      containersType.mixin.resources.mixinInstance({
            limits: _containerResourceV2.limits,
            requests: _containerResourceV2.requests,
        },
      ),
      

    // k.extensions.v1beta1.deployment.mixin.spec.template.spec.containersType.new(
    //   name, tosAppConfig.image
    // ).withImagePullPolicy(
    //   'Always'
    // ).withEnv(if std.objectHas(tosAppConfig, 'env_list') then tosAppConfig.env_list else []) +
    // if std.objectHas(tosAppConfig, 'resources') then $.TosContainerResources(tosAppConfig.resources) else {},

  // Kubernetes Pod spec.template的containers函数定义
  transwarpPodSpecTemplate(componentConfig={}, initContainers=[], containers=[], volumes=[])::
    deployment.mixin.spec.template.spec.mixinInstance(
      templateSpecType.new() +
      {priorityClassName: $.commonlib.convertPriorityClassName(if std.objectHas(componentConfig, 'priority') then componentConfig.priority else '0' )} +
      templateSpecType.hostNetwork(if std.objectHas(componentConfig, 'use_host_network') then componentConfig.use_host_network else 'false') +
      templateSpecType.terminationGracePeriodSeconds(30) +
      templateSpecType.initContainers(initContainers) +
      templateSpecType.containers(containers) +
      templateSpecType.volumes(volumes),
    ),

  transwarpServiceAccountName(moduleName='', name='', metaConfig={})::
    local _fixModuleName = if std.length(name) > 0 then name else moduleName;
    local _name = $.transwarpReleaseName(_fixModuleName, metaConfig);
    deployment.mixin.spec.template.spec.serviceAccountName(if std.length(_name) > 0 then _name else 'default' ),

  transwarpServiceMonitor(moduleName='', metaConfig={}, endpoints={}, metricsLabels={})::
    $.servicemonitor.v1.serviceMonitor.new() +
    $.servicemonitor.v1.serviceMonitor.mixin.metadata.name(metaConfig.helmReleaseName) +
    $.servicemonitor.v1.serviceMonitor.mixin.metadata.annotations($.transwarpObjectAnnotations(moduleName, metaConfig)) +
    $.servicemonitor.v1.serviceMonitor.mixin.metadata.labels($.transwarpObjectLabels(moduleName, metaConfig)) +
    $.servicemonitor.v1.serviceMonitor.mixin.spec.jobLabel('transwarp') +
    $.servicemonitor.v1.serviceMonitor.mixin.spec.labelSelector.mixinInstance({
      matchLabels: $.transwarpObjectTemplateSelector(moduleName, metaConfig) + metricsLabels
    }) +
    $.servicemonitor.v1.serviceMonitor.mixin.spec.namespaceSelector.mixinInstance({matchNames: [ metaConfig.helmReleaseNamespace ]}) +
    $.servicemonitor.v1.serviceMonitor.mixin.spec.endpoints.mixinInstance(endpoints),
  
  // Kubernetes Role函数定义
  transwarpRole(moduleName='', name='', metaConfig={}, rules={})::
    local _fixModuleName = if std.length(name) > 0 then name else moduleName;
    local _name = $.transwarpReleaseName(_fixModuleName, metaConfig);
    role.new() +
    role.rules(rules) + 
    role.mixin.metadata.name(_name) +
    role.mixin.metadata.labels($.transwarpObjectLabels(moduleName, metaConfig)) +
    role.mixin.metadata.namespace($.transwarpNamespace(metaConfig)),

  transwarpRoleRule(apiGroups=[""], resources=["pods"], verbs=["get"])::
    policyRule.new() +
    policyRule.apiGroups(apiGroups) + 
    policyRule.resources(resources) +
    policyRule.verbs(verbs),
  
  // Kubernetes RoleBinding函数定义
  transwarpRoleBinding(moduleName='', name='', metaConfig={}, subjects={}, roleRef={})::
    local _fixModuleName = if std.length(name) > 0 then name else moduleName;
    local _name = $.transwarpReleaseName(_fixModuleName, metaConfig);
    roleBinding.new() +
    roleBinding.subjects(subjects) +
    roleBinding.mixin.metadata.name(_name) +
    roleBinding.mixin.metadata.labels($.transwarpObjectLabels(moduleName, metaConfig)) +
    roleBinding.mixin.metadata.namespace($.transwarpNamespace(metaConfig)) +
    roleBinding.mixin.roleRef.mixinInstance(roleRef),

  transwarpRoleSubjects(moduleName='', name='', metaConfig={}, kind='ServiceAccount')::
    local _fixModuleName = if std.length(name) > 0 then name else moduleName;
    local _name = $.transwarpReleaseName(_fixModuleName, metaConfig);
    roleSubjectsType.new() +
    roleSubjectsType.name(_name) + 
    roleSubjectsType.namespace($.transwarpNamespace(metaConfig)) +
    roleSubjectsType.kind(kind),

  transwarpRoleRef(moduleName='', name='', metaConfig={}, apiGroup='rbac.authorization.k8s.io', kind='Role')::
    local _fixModuleName = if std.length(name) > 0 then name else moduleName;
    local _name = $.transwarpReleaseName(_fixModuleName, metaConfig);
    roleRefType.new() +
    roleRefType.name(_name) +
    roleRefType.apiGroup(apiGroup) +
    roleRefType.kind(kind),

  // Kubernetes ServiceAccount函数定义
  transwarpServiceAccount(moduleName='', name='', metaConfig={})::
    local _fixModuleName = if std.length(name) > 0 then name else moduleName;
    local _name = $.transwarpReleaseName(_fixModuleName, metaConfig);
    serviceAccount.new() +
    serviceAccount.mixin.metadata.name(_name) +
    serviceAccount.mixin.metadata.labels($.transwarpObjectLabels(moduleName, metaConfig)) +
    serviceAccount.mixin.metadata.namespace($.transwarpNamespace(metaConfig)),

}
