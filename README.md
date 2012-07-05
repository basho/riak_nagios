# A Repository for reusable nagios monitoring scripts.

### A Basic Nagios Primer

* A Nagios check is a shell script

* This is the documentation for them: http://nagiosplug.sourceforge.net/developer-guidelines.html

* The most important part to a nagios script is the return codes.

  >  0 OK  
  >  1 Warning   
  >  2 Critical  
  >  3 Unknown  
  
* Can be written in any language as long as the exit codes are right.

  * Perl is the standard
  * Python / Bash is usually installed by default, and easier to work with
  * Ruby is not usually installed by default

### Riak Nagios

#### Building

```bash
make escript
```

#### Deployment

```bash
scp check_node root@s3p406.san2:/usr/sbin/
```

#### NRPE

Riak related checks are configured in `/etc/nagios/nrpe.d/riak.cfg`, for example:

```
command[check_riak_up]=/usr/lib/riak/erts-5.8.5/bin/escript check_node --node riak@s3p406.san2 riak_kv_up
command[check_riak_repl]=/usr/lib/riak/erts-5.8.5/bin/escript check_node --node riak@s3p406.san2 riak_repl
command[check_riak_cs_up]=/usr/lib/riak/erts-5.8.5/bin/escript check_node --node riak_cs@s3p406.san2 node_up
```

After any change to this file, you'll need to restart the nrpe server. On ubuntu, that's as easy as `service nagios-nrpe-server restart`

You can find the current nrpe config files in the cfg directory

##### Testing NRPE

Once it's configured, you can use this nrpe plugin to test. If you see any of the possible status messages, and not the 
`NRPE: Unable to read output` error, your nrpe monitors are working.

```
/usr/lib/nagios/plugins/check_nrpe -H 127.0.0.1 -c check_riak_up
/usr/lib/nagios/plugins/check_nrpe -H 127.0.0.1 -c check_riak_repl
```

## Response

#### check_riak_up 

* On critical alert: Riak needs to be restarted by signing in and running `riak start`. If alerts continue to be triggered after restarting Riak, open a ticket with Basho.

#### check_riak_repl

* On critical alert: the check_node script received an unexpected return from Riak and further investigation is required. Open a ticket with Basho.
* On warning alert: the check_node script detected a socket error. The script automatically informs Riak of the error and Riak resets the connection. No action is required.
