## Logs

We strongly recommend storing logs in one centralized place when working in a clustered environment.
MongooseIM uses the standard OTP logging framework: [Logger][Logger].
Its handlers can be replaced and customised, according to Logger's documentation.

### Syslog integration

MongooseIM uses `syslogger` as a Logger handler for syslog.
To activate it you have to add `syslogger` to the applications section in `src/mongooseim/app.src`:

    %% syslogger, % uncomment to enable a logger handler for syslog

You also need to edit `rel/files/app.config` and uncomment the lines:

     % Uncomment these lines to enable logging to syslog.
     % Remember to add syslogger as a dependency in mongooseim.app.src.
    %% {syslogger, [
    %%     {ident, "mongooseim"},
    %%     {logger, [
    %%         {handler, sys_log, syslogger,
    %%          #{formatter => {logger_formatter, #{single_line => true}}}}]}]
    %% },

You can provide different parameters to change the handler's behaviour as described
in the `syslogger's` [GitHub page](https://github.com/NelsonVides/syslogger/):

* `ident` - a string to tag all the syslog messages with.
 The default is `mongooseim`.
* `facility` -  the facility to log to (see the syslog documentation).
* `log_opts` - see the syslog documentation for the description.

Depending on the system you use, remember to also add the appropriate line in the syslog config file.
For example, if the facility `local0` is set:

    local0.info                     /var/log/mongooseim.log

All the logs of level `info` should be passed to the `/var/log/mongooseim.log` file.

Example log (e.g `tail -f /var/log/mongooseim.log`):

    Apr  1 12:36:49 User.local mongooseim[6068]: [info] <0.7.0> Application mnesia started on node mongooseim@localhost

### Further / multiserver integration

For more advanced processing and analysis of logs, including gathering logs from multiple machines,
you can use one of the many available systems (e.g. logstash/elasticsearch/kibana, graylog, splunk),
by redirecting mongoose logs to such service with an appropriate [Logger][Logger]'s handler.

Check [Logging](Logging.md) for more information.

## Monitoring

### WombatOAM

WombatOAM is an operations and maintenance framework for Erlang based systems.
Its Web Dashboard displays this data in an aggregated manner.
Additionally, WombatOAM provides interfaces to feed the data to other OAM tools such as Graphite, Nagios or Zabbix.

For more information see: [WombatOAM](https://www.erlang-solutions.com/products/wombat-oam.html).

### OS level metrics: graphite-collectd

To monitor MongooseIM node during load testing, we recommend the following open source applications:

- [Grafana](https://grafana.com/) is used for data presentation.
- [Prometheus](https://prometheus.io) is a server used for metrics storage. Alternatively, MongooseIM also works with [Graphite](http://graphiteapp.org/).
- [collectd](http://collectd.org/) is a daemon running on the monitored nodes capturing data related to CPU and Memory usage, IO etc.

### Application metrics

MongooseIM uses [Prometheus](https://prometheus.io/) as the default metrics solution, but also supports Exometer with Graphite exporter.
Enable the chosen one in the [instrumentation section](../configuration/instrumentation.md).

#### Prometheus

MongooseIM exposes metrics in the Prometheus format by default.
More information about configuration can be found in [the HTTP listeners section](../listeners/listen-http.md#handler-types-prometheus-mongoose_prometheus_handler).

#### Exometer

MongooseIM uses [a fork of Exometer library](https://github.com/esl/exometer_core) for collecting metrics.
Exometer has many plug-in reporters that can send metrics to external services.
We maintain [exometer_report_graphite](https://github.com/esl/exometer_report_graphite), which can be enabled in the [instrumentation section of the configuration file](../configuration/instrumentation.md#exometer-reporter-options).

Moreover, Exometer metrics can be accessed through the GraphQL API.

#### GraphQL metrics endpoint

When using Exometer, the metrics can be accessed through <a href="../admin-graphql-doc.html#query-metric" target="_blank" rel="noopener noreferrer">a GraphQL query</a>.
With Prometheus, this query will not work, however, the metrics will be available in the Prometheus format from [the configured endpoint](../listeners/listen-http.md#listenhttphandlerspath).

### Run Graphite & Grafana in Docker - quick start

The following commands will download the latest version of `kamon/grafana_graphite` docker image that contains both Grafana and Graphite, and start them while mounting the local directory `./docker-grafana-graphite-master/data` for metric persistence:

```bash
curl -SL https://github.com/kamon-io/docker-grafana-graphite/archive/master.tar.gz | tar -xzf -
make -C docker-grafana-graphite-master up
```

Go to [http://localhost:80](http://localhost:80) to view the Grafana dashboard that's already set up to use metrics from Graphite.

### Add metrics to Grafana dashboard

We recommend the following metrics as a baseline for tracking your MongooseIM installation.
For time-based metrics, you can choose to display multiple calculated values for a reporting period - we recommend tracking at least `max`, `median` and `mean`.

```
Session count:                   <prefix>.global.sm_total_sessions.count
Outgoing XMPP messages:          <prefix>.<domain>.xmpp_element_out.c2s.message_count.one
Incoming XMPP messages:          <prefix>.<domain>.xmpp_element_in.c2s.message_count.one
Successful logins:               <prefix>.<domain>.sm_session.logins.one
Logouts:                         <prefix>.<domain>.sm_session.logouts.one
Authorization time:              <prefix>.<domain>.backends.auth.authorize.<value-type>
RDBMS "simple" query time:       <prefix>.<domain>.backends.mongoose_rdbms.query.<value-type>
RDBMS prepared query time:       <prefix>.<domain>.backends.mongoose_rdbms.execute.<value-type>
MAM lookups:                     <prefix>.<domain>.mam_lookup_messages.one
MAM archivization time:          <prefix>.<domain>.backends.mod_mam_pm.archive.<value-type>
MAM lookup time:                 <prefix>.<domain>.backends.mod_mam_pm.lookup.<value-type>
MAM private messages flush time: <prefix>.<domain>.mod_mam_rdbms_async_pool_writer.flush_time.<value-type>
MAM MUC messages flush time:     <prefix>.<domain>.mod_mam_muc_rdbms_async_pool_writer.flush_time.<value-type>
```

Note that RDBMS metrics are only relevant if MongooseIM is [configured with an RDBMS backend](../configuration/database-backends-configuration.md), MAM metrics when [mod_mam is enabled](../modules/mod_mam.md) and MAM flush times when MAM is configured with an RDBMS backend with `async_writer` option (default).

#### Example graph in Grafana

![An example graph in Grafana](example-grafana-graph.png)

This screenshot shows a graph plotting the RDBMS simple query time metric mentioned above.
The graph is plotted for three nodes with each node having a different prefix: `mongoose.node1`, `mongoose.node2` and `mongoose.node3`.

The queries take metrics for all nodes and all domains (`**` is a wildcard for multiple parts of the metric name) and group them *per-node* and *per-value-type* (respectively `1`st and `-1`st part of the metric's name).
Parts of the names are indexed from `0`.

Time-based metrics in MongooseIM are given in **microseconds**, so to display human-readable values in graph's legend, the Y-axis unit has to be edited on the `Axes` tab.

[Logger]: https://erlang.org/doc/apps/kernel/logger_chapter.html#handlers
