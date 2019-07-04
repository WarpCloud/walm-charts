#!/bin/bash
set -x

export KAFKA_LOG_DIRS=/var/log/kafka
export KAFKA_CONF_DIR=/etc/kafka/conf
export KAFKA_HOSTNAME=$(echo "`hostname -f`" | sed -e 's/^[ \t]*//g' -e 's/[ \t]*$//g')

export BROKER_ID=${HOSTNAME##*-}

JMX_PORT=${JMX_PORT:-9999}

mkdir -p ${KAFKA_CONF_DIR} ${KAFKA_LOG_DIRS} /data
chown kafka:kafka ${KAFKA_CONF_DIR} ${KAFKA_LOG_DIRS} /data

confd -onetime -backend file -prefix / -file /etc/confd/kafka-confd.conf

[ -s /etc/guardian-site.xml ] && {
  cp /etc/guardian-site.xml $KAFKA_CONF_DIR
}

KAFKA_ENV=$KAFKA_CONF_DIR/kafka-env.sh

JMXEXPORTER_ENABLED=${JMXEXPORTER_ENABLED:-"false"}
JMX_EXPORTER_JAR=`ls /usr/lib/jmx_exporter/jmx_prometheus_javaagent-*.jar | head -n1`
[ "${JMXEXPORTER_ENABLED}" = "true" ] && \
  export JMXEXPORTER_OPTS=" -javaagent:${JMX_EXPORTER_JAR}=${JMXEXPORTER_PORT:-"19009"}:/usr/lib/jmx_exporter/configs/kafka.yml "

export KAFKA_JMX_OPTS="-Dcom.sun.management.jmxremote=true -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote.rmi.port=$JMX_PORT\
 -Dcom.sun.management.jmxremote.port=$JMX_PORT"


[ -f $KAFKA_ENV ] && {
  source $KAFKA_ENV
}
[ -f /etc/tdh-env.sh ] && {
  source /etc/tdh-env.sh
  setup_keytab

}

CLASSPATH=""
set +x
for jar in `find /usr/lib/kafka -name "*.jar"`
do
   CLASSPATH+=":$jar"
done
for jar in `find /usr/lib/guardian-plugins/lib -name "*.jar"`
do
   CLASSPATH+=":$jar"
done
CLASSPATH+=":${KAFKA_CONF_DIR}"
set -x

JAVA_OPTS="-Xmx${KAFKA_SERVER_MEMORY} \
-Xms${KAFKA_SERVER_MEMORY} \
-XX:+UseCompressedOops \
-XX:+UseParNewGC \
-XX:+UseConcMarkSweepGC \
-XX:+CMSClassUnloadingEnabled \
-XX:+CMSScavengeBeforeRemark \
-XX:+DisableExplicitGC \
-Djava.awt.headless=true \
-Xloggc:${KAFKA_LOG_DIRS}/kafkaServer-gc.log \
-verbose:gc \
-XX:+PrintGCDetails \
-XX:+PrintGCDateStamps \
-XX:+PrintGCTimeStamps \
-Dlog4j.configuration=file:/etc/kafka/conf/log4j.properties \
-Dkafka.logs.dir=${KAFKA_LOG_DIRS}/kafkaServer.log \
$JMXEXPORTER_OPTS $KAFKA_JMX_OPTS $JAVA_OPTS"

$JAVA_HOME/bin/java $JAVA_OPTS -cp $CLASSPATH kafka.Kafka /etc/kafka/conf/server.properties
