{
  local kube = self,

  matchTosVersion(config={}, version='')::
    if std.objectHas(config, 'TosVersion') then
      if config.TosVersion == '1.9' then true
      else if config.TosVersion == version then true
      else false
    else if version == '1.2' then true
    else false,

  haAdapter(config={}, ha='', non_ha='')::
    if config.use_high_availablity then ha
    else non_ha,

  installName(name, config={})::
    if std.length(name) > 0 then name + config.Transwarp_Install_ID else '',

  cniNetwork(config={})::
    if std.objectHas(config, 'Transwarp_Cni_Network') && std.length(config.Transwarp_Cni_Network) > 0 then config.Transwarp_Cni_Network else 'overlay',

  tos:: {
    Base(wrapped, config):
      wrapped,
    ReplicationController(wrapped, config):
      local base = kube.tos.Base(wrapped, config);
      base {
        spec+: {
          [if $.tos.UserDefinedApplicationPause(config) then 'replicas']: 0,
        },
      },

    ConfigMap(wrapped, config):
      $.tos.ConfigMap(wrapped, config),

    Ingress(wrapped, config):
      $.tos.Ingress(wrapped, config),

    PdReplicationController(wrapped, config):
      $.tos.ReplicationController(wrapped, config),

    DaemonSet(wrapped, config):
      local base = kube.tos.Base(wrapped, config);
      local moduleName = base.spec.template.metadata._moduleName;
      // TODO fix pause daemonset with node selector
      base {
        spec+: {
          template+: $.tos.PodTemplateFinalizer(super.template, moduleName, config),
        },
      },

    Deployment(wrapped, config):
      local base = kube.tos.Base(wrapped, config);
      local moduleName = base.spec.template.metadata._moduleName;
      base {
        spec+: {
          [if $.tos.UserDefinedApplicationPause(config) then 'replicas']: 0,
          template+: $.tos.PodTemplateFinalizer(super.template, moduleName, config),
        },
      },

    Job(wrapped, config):
      local base = kube.tos.Base(wrapped, config);
      local moduleName = base.spec.template.metadata._moduleName;
      base {
        spec+: {
          template+: $.tos.PodTemplateFinalizer(super.template, moduleName, config),
        },
      },

    StatefulSet(wrapped, config):
      local base = kube.tos.Base(wrapped, config);
      local moduleName = base.spec.template.metadata._moduleName;
      local generatedPvcs = kube.tos.UserDefinedPvcs(moduleName, config);
      base {
        spec+: {
          [if $.tos.UserDefinedApplicationPause(config) then 'replicas']: 0,
          template+: $.tos.PodTemplateFinalizer(super.template, moduleName, config) + {
            metadata+: {
              annotations+: {
                [if std.objectHas(config, 'Transwarp_Network_EnableStaticIP') && config.Transwarp_Network_EnableStaticIP then 'tos.network.staticIP']: 'true',
              },
            },
          },
        },
      },

    PodTemplateFinalizer(template, moduleName, config):
      local generatedAutoInjectvolumes = kube.tos.UserDefinedAutoInjectedVolume(config);
      template {
        metadata+: {
          [if !kube.matchTosVersion(config, '1.9') && std.objectHas(config, 'Transwarp_Affinity') &&
              std.objectHas(template.metadata, 'annotations') then 'annotations']+: {
            'scheduler.alpha.kubernetes.io/affinity': std.toString(config.Transwarp_Affinity),
          },
          [if !kube.matchTosVersion(config, '1.9') && std.objectHas(config, 'Transwarp_Affinity') &&
              !std.objectHas(template.metadata, 'annotations') then 'annotations']: {
            'scheduler.alpha.kubernetes.io/affinity': std.toString(config.Transwarp_Affinity),
          },
        },
        spec+: {
          containers: [$.tos.PodContainerFinalizer(c, c.name, moduleName, config) for c in super.containers],
          [if std.length(generatedAutoInjectvolumes) > 0 && std.objectHas(template.spec, 'volumes') then 'volumes']+: generatedAutoInjectvolumes,
          [if std.length(generatedAutoInjectvolumes) > 0 && !std.objectHas(template.spec, 'volumes') then 'volumes']: generatedAutoInjectvolumes,
          [if kube.matchTosVersion(config, '1.9') && std.objectHas(config, 'Transwarp_Affinity') &&
              std.objectHas(template.spec, 'affinity') then 'affinity']+: config.Transwarp_Affinity,
          [if kube.matchTosVersion(config, '1.9') && std.objectHas(config, 'Transwarp_Affinity') &&
              !std.objectHas(template.spec, 'affinity') then 'affinity']: config.Transwarp_Affinity,
          [if kube.matchTosVersion(config, '1.9') && std.objectHas(config, 'Transwarp_Config') &&
              std.objectHas(config.Transwarp_Config, 'Transwarp_Tolerations') then 'tolerations']: config.Transwarp_Config.Transwarp_Tolerations,
        },
      },

    PodContainerFinalizer(container, containerName, moduleName, config):
      local superResources = if std.objectHas(container, 'resources') then container.resources else {};
      local generatedAutoInjectvolumeMounts = kube.tos.UserDefinedAutoInjectedVolumeMounts(config);
      local env = if std.objectHas(container, 'env') then container.env else [];
      local finalizerEnv = if std.objectHas(config, 'Transwarp_Finalizer_Env_List')
                              && std.length(config.Transwarp_Finalizer_Env_List) > 0 then
        kube.tos.Generate_env_list(config.Transwarp_Finalizer_Env_List, []) else [];

      container {
        [if std.length(generatedAutoInjectvolumeMounts) > 0 && std.objectHas(container, 'volumeMounts') then 'volumeMounts']+: generatedAutoInjectvolumeMounts,
        [if std.length(generatedAutoInjectvolumeMounts) > 0 && !std.objectHas(container, 'volumeMounts') then 'volumeMounts']: generatedAutoInjectvolumeMounts,
        [if std.objectHas(container, 'env') || std.objectHas(config, 'Transwarp_Finalizer_Env_List') then 'env']: kube.tos.AdaptToDownwardApi(env + finalizerEnv, config),
      },

    UserDefinedApplicationPause(config):
      // Use Transwarp_Application_Pause to set replicas of all pod template to 0
      std.objectHas(config, 'Transwarp_Application_Pause') && config.Transwarp_Application_Pause,

    UserDefinedAutoInjectedVolume(config):
      if std.objectHas(config, 'Transwarp_Config') && std.objectHas(config.Transwarp_Config, 'Transwarp_Auto_Injected_Volumes') &&
         std.length(config.Transwarp_Config.Transwarp_Auto_Injected_Volumes) > 0 then
        [
          { name: item.volumeName, secret: { secretName: item.secretname } }
          for item in config.Transwarp_Config.Transwarp_Auto_Injected_Volumes
        ]
      else
        [],

    UserDefinedAutoInjectedVolumeMounts(config):
      if std.objectHas(config, 'Transwarp_Config') && std.objectHas(config.Transwarp_Config, 'Transwarp_Auto_Injected_Volumes') &&
         std.length(config.Transwarp_Config.Transwarp_Auto_Injected_Volumes) > 0 then
        [
          { name: item.volumeName, mountPath: '/var/run/secrets/transwarp.io/tosvolume/' + item.volumeName }
          for item in config.Transwarp_Config.Transwarp_Auto_Injected_Volumes
        ]
      else
        [],

    Generate_env_list(config, default)::
      // step 0: type check
      if std.type(config) != 'array' then
        error ('std.filterMap first param must be array, got ' + std.type(config))
      else if std.type(default) != 'array' then
        error ('std.filterMap second param must be array, got ' + std.type(default))
      else
        // step 1: merge & remove duplicates(judge by 'key')
        local config_not_contains(ele) = std.foldl(function(x, y) if y.key == ele.key then false else x, config, true);
        local ans = config + std.filter(config_not_contains, default);

        // step 2: ouput answer, map {key: "", value: ""} to {name: ""， value: ""}
        std.map(function(ele) { name: ele.key, value: ele.value }, ans),

    AdaptToDownwardApi(env_list, config={})::
      if std.objectHas(config, 'TosVersion') && kube.matchTosVersion(config, '1.9') then [kube.tos.GenerateDownwardEnv(e) for e in env_list]
      else env_list,

    GenerateDownwardEnv(env)::
      {
        name: env.name,
        [if std.objectHas(env, 'valueFrom') then 'valueFrom']: env.valueFrom,
        [if std.objectHas(env, 'value') then 'value']: env.value,
      } + {
        [if std.objectHas(env, 'valueFrom') &&
            std.objectHas(env.valueFrom, 'fieldRef') &&
            std.objectHas(env.valueFrom.fieldRef, 'fieldPath') &&
            std.startsWith(env.valueFrom.fieldRef.fieldPath, 'metadata.annotations') then 'valueFrom']:
          local annotation_value = 'metadata.annotations' +
                                   "['" + std.substr(env.valueFrom.fieldRef.fieldPath,
                                                     std.length('metadata.annotations.'),
                                                     std.length(env.valueFrom.fieldRef.fieldPath) - std.length('metadata.annotations.'))
                                   + "']";
          {
            fieldRef: env.valueFrom.fieldRef {
              fieldPath: annotation_value,
            },
          },
      },
    Flannel:: {
      Env:
        ([
           {
             name: 'FLANNEL_SOCKET_PATH',
             value: '/var/run/flannel/flannel.sock',
           },
         ]),

      VolumeMounts:
        ([
           {
             mountPath: '/var/run/flannel',
             name: 'flanneldir',
           },
         ]),

      HostPath(config={}):
        kube.v1.HostPath(name='flanneldir', path=('/var/run/hadoop-flannel/' + $.cniNetwork(config))),
    },
  },

  v1:: {

    local ApiVersion = {
      apiVersion: 'v1',
    },

    Metadata(name='', generateName='', config={}): {
      [if std.length(name) > 0 then 'name']: name,
      [if std.length(generateName) > 0 then 'generateName']: generateName,
      [if std.objectHas(config, 'Customized_Namespace') && std.length(config.Customized_Namespace) > 0 then 'namespace']: config.Customized_Namespace,
    },

    ReplicationController(name='', generateName='', moduleName='', config={}): ApiVersion {
      local _moduleName = if std.length(moduleName) > 0 then moduleName else if std.length(name) > 0 then name else generateName,
      local _name = if std.length(name) > 0 then name + config.Transwarp_Install_ID else '',

      kind: 'ReplicationController',
      metadata: $.v1.Metadata(_name, generateName, config) {
        labels: $.ReservedLabels(_moduleName, config),
        // keep this in case in future, we need to add a common annotation
        annotations: {},
      },

      spec: {
        selector: $.ReservedSelector(_moduleName, config),
        template: $.v1.PodTemplate(_moduleName, config),
      },
    },

    ConvertPriorityClassName(priority=0)::
      if priority < 100 then 'low-priority'
      else if priority < 150 then 'medium-priority'
      else if priority < 200 then 'high-priority'
      else 'system-priority',

    ConfigMap(name='', generateName='', moduleName='', config={}): ApiVersion {
      local _moduleName = if std.length(moduleName) > 0 then moduleName else if std.length(name) > 0 then name else generateName,
      local _name = if std.length(name) > 0 then name + config.Transwarp_Install_ID else '',

      kind: 'ConfigMap',
      metadata: $.v1.Metadata(_name, generateName, config) {
        labels: $.ReservedLabels(_moduleName, config),
        // keep this in case in future, we need to add a common annotation
        annotations: {},
      },

      data: {
      },
    },

    PdReplicationController(name='', generateName='', moduleName='', pdContainerName='pd', config={}): $.v1.ReplicationController(name, generateName, moduleName, config) {
      local _moduleName = if std.length(moduleName) > 0 then moduleName else if std.length(name) > 0 then name else generateName,
      //            metadata+: {
      //                labels+: {
      //                    [moduleName]: "1"
      //                },
      //            },
      spec+: {
        template+: {
          metadata+: {
            annotations:: super.annotations,
            labels+: {
              //                           [_moduleName + ".install." + config.Transwarp_Install_ID]: "true",
              //                           [_moduleName]: "1",
              'transwarp.pd.pod': 'true',
            },
          },
          spec+: {
            containers: [
              $.v1.PodContainer(pdContainerName) {
                args: [
                  'ls',
                ],
                image: std.toString(config.Transwarp_Registry_Server) + '/jenkins/transwarppd:live',
                imagePullPolicy:: super.imagePullPolicy,
              },
            ],
            podDiskSpec: {
              isPersistentDirPod: true,
            },
            restartPolicy: 'OnFailure',
          },
        },
      },

    },

    Service(name='', generateName='', moduleName='', selectorModuleName='', config={}): ApiVersion {
      local _moduleName = if std.length(moduleName) > 0 then moduleName else if std.length(name) > 0 then name else generateName,
      local _name = if std.length(name) > 0 then name + config.Transwarp_Install_ID else '',
      local _selectorModuleName = if std.length(selectorModuleName) > 0 then selectorModuleName else _moduleName,

      kind: 'Service',
      metadata: $.v1.Metadata(_name, generateName, config) {
        labels: $.ReservedLabels(_moduleName, config) + {
          'k8s-app': _moduleName,
        },
        annotations: {},
      },
      spec: {
        selector: $.ReservedSelector(_selectorModuleName, config),
      },
    },

    NodePortService(name='', generateName='', moduleName='', selectorModuleName='', config={}): $.v1.Service(name, generateName, moduleName, selectorModuleName, config) {
      metadata+: {
        labels+: {
          'kubernetes.io/cluster-service': 'true',
        },
      },

      spec+: {
        type: 'NodePort',
      },
    },

    HeadlessService(name='', generateName='', moduleName='', selectorModuleName='', config={}): $.v1.Service(name, generateName, moduleName, selectorModuleName, config) {
      metadata+: {
        labels+: {
          'kubernetes.io/headless-service': 'true',
        },
      },
      spec+: {
        clusterIP: 'None',
      },
    },


    DummyService(providesInfo={}, config={}): $.v1.Service(name='app-dummy-', moduleName='dummy', config=config) {
      local metaAnnotation = {
        [if std.length(providesInfo) > 0 then 'provides']: providesInfo,
      },
      local _app_labels = if std.objectHasAll(config, 'Transwarp_App_Labels') && std.length(config.Transwarp_App_Labels) > 0 then config.Transwarp_App_Labels else {},

      metadata+: {
        annotations+: {
          [if std.length(metaAnnotation) > 0 then 'transwarp.meta']: std.toString(metaAnnotation),
        },
        labels: $.ReservedLabels('app-dummy', config) + {
          'transwarp.meta': 'true',
          'transwarp.svc.scope': 'app',
          [if std.objectHasAll(config, 'Transwarp_App_Scope') && std.length(config.Transwarp_App_Scope) > 0 then 'transwarp.scope']: config.Transwarp_App_Scope,
        } + _app_labels,
      },
      spec: {
        clusterIP: 'None',
        ports: [{
          port: 5000,
          targetPort: 5000,
        }],
        selector: {},
      },
    },

    PodTemplate(moduleName, config): {
      metadata: $.v1.Metadata() {
        _moduleName:: moduleName,
        annotations: $.ReservedPodAnnotations(config),
        labels: $.ReservedLabels(moduleName, config) {
          [if std.objectHasAll(config, 'Transwarp_App_Meta') && std.length(config.Transwarp_App_Meta) > 0 && std.objectHasAll(config.Transwarp_App_Meta, 'name') then 'transwarp.meta.app.name']: config.Transwarp_App_Meta.name,
          [if std.objectHasAll(config, 'Transwarp_App_Meta') && std.length(config.Transwarp_App_Meta) > 0 && std.objectHasAll(config.Transwarp_App_Meta, 'version') then 'transwarp.meta.app.version']: config.Transwarp_App_Meta.version,
          [if std.objectHasAll(config, 'Transwarp_App_Meta') && std.length(config.Transwarp_App_Meta) > 0 && std.objectHasAll(config.Transwarp_App_Meta, 'id') then 'transwarp.meta.app.id']: std.toString(config.Transwarp_App_Meta.id),
        },
      },
      spec: {
      },
    },

    PodContainer(name): {
      imagePullPolicy: 'Always',
      name: name,
    },

    PersistentDirVolume(name, selector): {
      name: name,
      persistentDir: {
        podSelector: selector,
      },
    },

    PersistentVolumeClaim(name, moduleName, storageConfig={}, config={}, annotations={},): {
      metadata: $.v1.Metadata(name) {
        labels: $.ReservedLabels(moduleName, config),
        annotations: {
          'volume.beta.kubernetes.io/storage-class': storageConfig.storageClass,
        } + annotations,
      },
      spec: {
        accessModes: storageConfig.accessModes,
        resources: {
          requests: {
            storage: storageConfig.size,
          },
          [if std.objectHas(storageConfig, 'limits') && std.length(storageConfig.limits) > 0 then 'limits']: storageConfig.limits,
        },
      },
    },

    HostPath(name, path): {
      name: name,
      hostPath: {
        path: path,
      },
    },

    TosDisk(name, storageConfig): {
      name: name,
      tosDisk: {
        name: name,
        storageType: storageConfig.storageClass,
        capability: storageConfig.size,
        accessMode: storageConfig.accessMode,
      },
    },

    HostShareDirVolume(name, path, namespace=''): {
      name: name,
      hostShareDir: {
        path: path,
        [if std.length(namespace) != 0 then 'namespace']: namespace,
      },
    },
    ContainerResources(cpu_request=0, memory_limit=0, cpu_limit=0, memory_request=0): {
      local _cpu_request = if std.type(cpu_request) == 'object' && std.objectHas(cpu_request, 'request') then cpu_request.request else cpu_request,
      local _cpu_limit = if std.type(cpu_request) == 'object' && std.objectHas(cpu_request, 'limit') then cpu_request.limit else cpu_limit,
      local _memory_request = if std.type(memory_limit) == 'object' && std.objectHas(memory_limit, 'request') then memory_limit.request else memory_request,
      local _memory_limit = if std.type(memory_limit) == 'object' && std.objectHas(memory_limit, 'limit') then memory_limit.limit else memory_limit,
      limits: {
        [if _memory_limit > 0 then 'memory']: std.toString(_memory_limit) + 'Gi',
        [if _cpu_limit > 0 then 'cpu']: std.toString(_cpu_limit),
      },
      requests: {
        [if _memory_request > 0 then 'memory']: std.toString(_memory_request) + 'Gi',
        [if _cpu_request > 0 then 'cpu']: std.toString(_cpu_request),
      },
    },

    ContainerResourcesV2(config): {
      local _cpu_request = if std.objectHas(config, 'cpu_request') then config.cpu_request else 0,
      local _cpu_limit = if std.objectHas(config, 'cpu_limit') then config.cpu_limit else 0,
      local _memory_request = if std.objectHas(config, 'memory_request') then config.memory_request else 0,
      local _memory_limit = if std.objectHas(config, 'memory_limit') then config.memory_limit else 0,
      local _gpu_request = if std.objectHas(config, 'gpu_request') then config.gpu_request else 0,
      local _gpu_limit = if std.objectHas(config, 'gpu_limit') then config.gpu_limit else 0,
      limits: {
        [if _memory_limit > 0 then 'memory']: std.toString(_memory_limit) + 'Gi',
        [if _cpu_limit > 0 then 'cpu']: std.toString(_cpu_limit),
        [if _gpu_limit > 0 then 'nvidia.com/gpu']: _gpu_limit,
      },
      requests: {
        [if _memory_request > 0 then 'memory']: std.toString(_memory_request) + 'Gi',
        [if _cpu_request > 0 then 'cpu']: std.toString(_cpu_request),
        [if _gpu_request > 0 then 'nvidia.com/gpu']: _gpu_request,
      },
    },

    EnvFieldPath(name, path): {
      name: name,
      valueFrom: {
        fieldRef: {
          fieldPath: path,
        },
      },
    },
  },

  'apps/v1beta1':: {
    local ApiVersion = {
      apiVersion: 'apps/v1beta1',
    },

    StatefulSet(name='', generateName='', moduleName='', config={}): ApiVersion {
      local _moduleName = if std.length(moduleName) > 0 then moduleName else if std.length(name) > 0 then name else generateName,
      local _installName = kube.installName(name, config),
      kind: 'StatefulSet',
      metadata: $.v1.Metadata(_installName, generateName, config) {
        annotations: {},
        labels: $.ReservedLabels(_moduleName, config),
      },
      spec: {
        [if kube.matchTosVersion(config, '1.9') then 'updateStrategy']: {
          type: 'RollingUpdate',
        },
        [if kube.matchTosVersion(config, '1.9') then 'podManagementPolicy']: 'Parallel',
        serviceName: _installName,
        selector: {
          matchLabels: $.ReservedSelector(_moduleName, config),
        },
        template: $.v1.PodTemplate(_moduleName, config),
      },
    },
  },

  'batch/v1':: {
    local ApiVersion = {
      apiVersion: 'batch/v1',
    },

    Job(name='', generateName='', moduleName='', config={}): ApiVersion {
      local _moduleName = if std.length(moduleName) > 0 then moduleName else if std.length(name) > 0 then name else generateName,
      local _name = if std.length(name) > 0 then name + config.Transwarp_Install_ID else '',
      kind: 'Job',
      metadata: $.v1.Metadata(_name, generateName, config) {
        annotations: {},
        labels: $.ReservedLabels(_moduleName, config),
      },
      spec: {
        completions: 1,
        parallelism: 1,
        template: $.v1.PodTemplate(_moduleName, config),
      },
    },
  },


  'extensions/v1beta1':: {
    local ApiVersion = {
      apiVersion: 'extensions/v1beta1',
    },

    Deployment(name='', generateName='', moduleName='', config={}): ApiVersion {
      local _moduleName = if std.length(moduleName) > 0 then moduleName else if std.length(name) > 0 then name else generateName,
      local _name = if std.length(name) > 0 then name + config.Transwarp_Install_ID else '',
      kind: 'Deployment',
      metadata: $.v1.Metadata(_name, generateName, config) {
        annotations: {},
        labels: $.ReservedLabels(_moduleName, config),
      },
      spec: {
        selector: {
          matchLabels: $.ReservedSelector(_moduleName, config),
        },
        template: $.v1.PodTemplate(_moduleName, config),
      },
    },

    Ingress(name='', generateName='', moduleName='', config={}): ApiVersion {
      local _moduleName = if std.length(moduleName) > 0 then moduleName else if std.length(name) > 0 then name else generateName,
      local _name = if std.length(name) > 0 then name + config.Transwarp_Install_ID else '',

      kind: 'Ingress',
      metadata: $.v1.Metadata(_name, generateName, config) {
        labels: $.ReservedLabels(_moduleName, config),
        // keep this in case in future, we need to add a common annotation
        annotations: {},
      },

      spec: {
      },
    },

    DeploymentStrategy(config={}):
      if std.type(config) != 'object' then
        error ('config must be an object')
      else if std.length(config) == 0 then
        {}
      else if !std.objectHas(config, 'type') then
        error ('config does not have type attribute')
      else if config.type == 'Recreate' then
        {
          type: 'Recreate',
        }
      else if config.type == 'RollingUpdate' then
        {
          type: 'RollingUpdate',
          rollingUpdate: {
            maxUnavailable: config.rolling_update_configs.max_unavailable,
            maxSurge: config.rolling_update_configs.max_surge,
          },
        }
      else
        error ('invalid configs for Deployment Strategy '),


    DaemonSet(name='', generateName='', moduleName='', config={}): ApiVersion {
      local _moduleName = if std.length(moduleName) > 0 then moduleName else if std.length(name) > 0 then name else generateName,
      local _name = if std.length(name) > 0 then name + config.Transwarp_Install_ID else '',
      kind: 'DaemonSet',
      metadata: $.v1.Metadata(_name, generateName, config) {
        labels: $.ReservedLabels(_moduleName, config),
      },
      spec: {
        [if kube.matchTosVersion(config, '1.9') then 'updateStrategy']: {
          type: 'RollingUpdate',
          rollingUpdate: { maxUnavailable: '100%' },
        },
        selector: {
          matchLabels: $.ReservedSelector(_moduleName, config),
        },
        template: $.v1.PodTemplate(_moduleName, config),
      },
    },

  },

  instance_selector(config)::
    if std.objectHasAll(config, 'Customized_Instance_Selector') && std.length(config.Customized_Instance_Selector) > 0 then
      config.Customized_Instance_Selector
    else {
      'transwarp.install': config.Transwarp_Install_ID,
    },

  ReservedLabels(moduleName, config):: {
    'transwarp.name': moduleName,
    [if std.objectHas(config, 'HelmAdditionalValues') then 'release']: config.HelmAdditionalValues.HelmNativeValues.releaseName,
    [if std.objectHas(config, 'Transwarp_Alias') && std.length(config.Transwarp_Alias) > 0 then 'transwarp.alias']: config.Transwarp_Alias,
  } + $.instance_selector(config),


  ReservedSelector(moduleName, config):: {
    'transwarp.name': moduleName,
  } + $.instance_selector(config),

  ReservedPodAnnotations(config):: {
    [if std.objectHas(config, 'Transwarp_App_Name') && std.length(config.Transwarp_App_Name) > 0 then 'transwarp.app']: config.Transwarp_App_Name,
    [if kube.matchTosVersion(config, '1.5') then 'cni.networks']: $.cniNetwork(config),
  } + (if std.objectHas(config, 'Transwarp_Configmap_MD5') then {
         'transwarp/configmap.md5': config.Transwarp_Configmap_MD5,
       } else {}),

  NameSpace(config)::
    if std.objectHas(config, 'Transwarp_Install_Namespace') && std.length(config.Transwarp_Install_Namespace) > 0 then config.Transwarp_Install_Namespace else 'default',

  AffinityAnnotations(nodeAffinity={}, podAffinity={}, podAntiAffinity={})::
    {
      [if std.length(nodeAffinity) > 0 then 'nodeAffinity']: nodeAffinity,
      [if std.length(podAffinity) > 0 then 'podAffinity']: podAffinity,
      [if std.length(podAntiAffinity) > 0 then 'podAntiAffinity']: podAntiAffinity,
    },

  NodeAntiAffinityAnnotations(config, moduleName='', nodeAffinity={}, podAffinity={})::
    local annotations = $.ReservedLabels(moduleName, config);
    local res =
      {
        requiredDuringSchedulingIgnoredDuringExecution:
          [{
            labelSelector: {
              matchLabels: annotations,
            },
            namespaces: [kube.NameSpace(config)],
            topologyKey: 'kubernetes.io/hostname',
          }],
      };
    local nodeAffinityConfig = (
      if std.length(nodeAffinity) > 0 then nodeAffinity
      else if std.objectHas(config, 'Transwarp_Config') &&
              std.objectHas(config.Transwarp_Config, 'Transwarp_Node_SelectorTerms') &&
              std.length(config.Transwarp_Config.Transwarp_Node_SelectorTerms) > 0
      then {
        requiredDuringSchedulingIgnoredDuringExecution: {
          nodeSelectorTerms: [
            { matchExpressions: config.Transwarp_Config.Transwarp_Node_SelectorTerms },
          ],
        },
      } else {}
    );
    $.AffinityAnnotations(nodeAffinity=nodeAffinityConfig, podAffinity=podAffinity, podAntiAffinity=res),

  NodeSoftAffinityAnnotations(config, moduleName='', nodeAffinity={}, podAffinity={})::
    local annotations = $.ReservedLabels(moduleName, config);
    local res =
      {
        preferredDuringSchedulingIgnoredDuringExecution:
          [{
            weight: 100,
            podAffinityTerm: {
              labelSelector: {
                matchLabels: annotations,
              },
              namespaces: [kube.NameSpace(config)],
              topologyKey: 'kubernetes.io/hostname',
            },
          }],
      };
    local config = $.AffinityAnnotations(nodeAffinity=nodeAffinity, podAffinity=podAffinity, podAntiAffinity=res);
    $.AffinityAnnotations(nodeAffinity=nodeAffinity, podAffinity=podAffinity, podAntiAffinity=res),

  // the hard requirement on affinity
  PodRequiredAffinity(config, affinity_label, affected_namespaces=[], pod_affinity_terms=[])::
    {
      requiredDuringSchedulingIgnoredDuringExecution: (if std.length(pod_affinity_terms) > 0
                                                       then pod_affinity_terms else
                                                         [{
                                                           labelSelector: {
                                                             matchLabels: affinity_label,
                                                           },
                                                           namespaces: affected_namespaces,
                                                           topologyKey: 'kubernetes.io/hostname',
                                                         }]),
    },

  // the soft requirement on affinity
  PodPreferredAffinity(config, affinity_label, affected_namespaces=[], weight=100, pod_affinity_terms=[])::
    {
      preferredDuringSchedulingIgnoredDuringExecution: (if std.length(pod_affinity_terms) > 0
                                                        then pod_affinity_terms else
                                                          [{
                                                            weight: weight,
                                                            podAffinityTerm: {
                                                              labelSelector: {
                                                                matchLabels: affinity_label,
                                                              },
                                                              namespaces: affected_namespaces,
                                                              topologyKey: 'kubernetes.io/hostname',
                                                            },
                                                          }]),
    },

  PodWeightedPodAffinityTerm(config, weight, affinity_term={}):: {
    weight: weight,
    podAffinityTerm: affinity_term,
  },

  PodAffinityTerm(config, affinity_label, affected_namespaces=[]):: {
    labelSelector: {
      matchLabels: affinity_label,
    },
    namespaces: affected_namespaces,
    topologyKey: 'kubernetes.io/hostname',
  },

  IngressCommon(_name, config, port)::
    kube['extensions/v1beta1'].Ingress(name=_name + '-', moduleName=_name, config=config) {
      metadata+: {
        annotations+: {
          'kubernetes.io/ingress.class': 'nginx',
          'nginx.ingress.kubernetes.io/proxy-body-size': '1024m',
          'nginx.ingress.kubernetes.io/affinity': 'cookie',
          'nginx.ingress.kubernetes.io/use-port-in-redirects': 'true',
          'nginx.ingress.kubernetes.io/enable-strip-uri': 'true',

          'nginx.ingress.kubernetes.io/rewrite-target': '/',
          'nginx.ingress.kubernetes.io/redirect-by-referer': 'true',
          'nginx.ingress.kubernetes.io/proxy-redirect-from': '$scheme://$host:$server_port/',
          'nginx.ingress.kubernetes.io/proxy-redirect-to': config.Transwarp_Config.Ingress.path + '/',
          'nginx.ingress.kubernetes.io/proxy-cookie-path': '/ ' + config.Transwarp_Config.Ingress.path + '/',

          'nginx.ingress.kubernetes.io/redirect-by-service-domain': 'true',
          'nginx.ingress.kubernetes.io/upstream-vhost': _name + '-' +
                                                        config.Transwarp_Install_ID + '.' + config.Transwarp_Install_Namespace + '.svc:' + port,
          'nginx.ingress.kubernetes.io/upstream-forwarded-host': _name + '-' +
                                                                 config.Transwarp_Install_ID + '.' + config.Transwarp_Install_Namespace + '.svc:' + port,
        },
      },
      spec+: {
        rules: [{
          http: {
            paths: [{
              path: config.Transwarp_Config.Ingress.path,
              backend: {
                serviceName: _name + '-' + config.Transwarp_Install_ID,
                servicePort: port,
              },
            }],
          },
        }],
      },
    },

}
