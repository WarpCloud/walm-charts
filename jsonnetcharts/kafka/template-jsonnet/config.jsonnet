{
  // system level params
  Transwarp_License_Address: '',
  Transwarp_Install_ID: '',
  Transwarp_Install_Namespace: '',
  Transwarp_Ingress: {
    http_port: 80,
    https_port: 443,
  },
  Customized_Instance_Selector: {},
  Customized_Namespace: '',
  // Transwarp_Application_Pause,

  App: {
    kafka: {
      update_strategy_configs: {
        type: 'Recreate',
      },
      priority: 0,
      replicas: 3,
      image: '172.16.1.99/gold/kafka:transwarp-6.0',
      env_list: [],
      use_host_network: false,
      resources: {
        cpu_limit: 2,
        cpu_request: 1,
        memory_limit: 8,
        memory_request: 4,
        storage: {
          log: {
            storageClass: 'silver',
            size: '20Gi',
            accessMode: 'ReadWriteOnce',
            limit: {},
          },
          data: {
            storageClass: 'silver',
            size: '500Gi',
            accessModes: ['ReadWriteOnce'],
            limit: {},
          },
        },
      },
    },
  },

  // security level params
  Transwarp_Config: {
    Transwarp_Auto_Injected_Volumes: [],
    Ingress: {},
    // Transwarp_Auto_Injected_Volumes: {
    //   kind: "Secret",
    //   selector: {
    //     "transwarp.keytab": "zookeeper",
    //   },
    //   volumeName: "keytab",
    // },
    msl_plugin_config: {
      enable: false,
      config: {
      },
    },
    security: {
      auth_type: 'none',
      guardian_client_config: {
        // guardian_realm: "TDH",
        guardian_site: {
          // guardian_serivce_id: ""
        },
      },
      cas_client_config: {
      },
      guardian_plugin_enable: 'false',
      cas_plugin_enable: 'false',
      sssd_plugin_enable: 'false',

      guardian_principal_host: 'tos',
      guardian_principal_user: 'kafka',
      // guardian_serivce_id: ""
    },
  },

  Advance_Config: {
    kafka: {
    },
    server_properties: {
      'num.network.threads': 3,
      'num.io.threads': 8,
      'socket.send.buffer.bytes': 102400,
      'socket.receive.buffer.bytes': 102400,
      'socket.request.max.bytes': 104857600,
      'log.dirs': '/data',
      'num.partitions': 3,
      'num.recovery.threads.per.data.dir': 1,
      'log.flush.interval.messages': 10000,
      'log.flush.interval.ms': 1000,
      'log.retention.hours': 6,
      'log.retention.bytes': 1073741824,
      'default.replication.factor': 2,
      'log.retention.check.interval.ms': 300000,
      'message.max.bytes': 100000000,
      'replica.fetch.max.bytes': 100000000,
      'zookeeper.connection.timeout.ms': 6000,
    },
  },

  // dependency
  GUARDIAN_CLIENT_CONFIG: {},
  ZOOKEEPER_CLIENT_CONFIG: {},
}
