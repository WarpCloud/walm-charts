#!/bin/bash
set -ex

export ZOOKEEPER_CONF_DIR=/etc/zookeeper/conf
export ZOOKEEPER_DATA_DIR=/var/transwarp
export ZOOKEEPER_DATA=$ZOOKEEPER_DATA_DIR/data
export ZOOKEEPER_CFG=$ZOOKEEPER_CONF_DIR/zoo.cfg

mkdir -p ${ZOOKEEPER_CONF_DIR}
mkdir -p $ZOOKEEPER_DATA

export MYID=${HOSTNAME##*-}
confd -onetime -backend file -prefix / -file /etc/confd/zookeeper-confd.conf

ZOOKEEPER_ENV=$ZOOKEEPER_CONF_DIR/zookeeper-env.sh

[ -f $ZOOKEEPER_ENV ] && {
  source $ZOOKEEPER_ENV
}
[ -f /etc/tdh-env.sh ] && {
  source /etc/tdh-env.sh
  setup_keytab
}
# ZOOKEEPER_LOG is defined in $ZOOKEEPER_ENV
mkdir -p $ZOOKEEPER_LOG_DIR
chown -R zookeeper:zookeeper $ZOOKEEPER_LOG_DIR
chown -R zookeeper:zookeeper $ZOOKEEPER_DATA

echo "Starting zookeeper service with config:"
cat ${ZOOKEEPER_CFG}

JMXEXPORTER_ENABLED=${JMXEXPORTER_ENABLED:-"true"}
if [ "${JMXEXPORTER_ENABLED}" == "true" ];then
  export JAVAAGENT_OPTS=" -javaagent:/usr/lib/jmx_exporter/jmx_prometheus_javaagent-0.7.jar=19000:/usr/lib/jmx_exporter/agentconfig.yml "
fi

sudo -u zookeeper java $SERVER_JVMFLAGS \
    $JAVAAGENT_OPTS \
    -cp $ZOOKEEPER_HOME/zookeeper-3.4.5-transwarp-with-dependencies.jar:$ZOOKEEPER_CONF_DIR \
    org.apache.zookeeper.server.quorum.QuorumPeerMain $ZOOKEEPER_CFG
