# A Repository for reusable nagios monitoring scripts.

### A Basic Nagios Primer 
(as told to Joe DeVivo by Sean Carey)

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
'./rebar compile'

#### Deployment
```
➜  riak_nagios git:(jnd-otp-version) scp ebin/riak_nagios.beam root@s3p406.san2:/usr/lib/riak/lib/basho-patches/.
➜  riak_nagios git:(jnd-otp-version) scp bin/nagtool root@s3p406.san2:/usr/lib/riak/erts-5.8.5/bin/nagtool
➜  riak_nagios git:(jnd-otp-version) scp bin/riak-nagios root@s3p406.san2:/usr/sbin/riak-nagios
```

You'll also have to attach to the riak console and `l(riak_nagios).` to reload the module.


#### Permisions
The Riak Nagios checks usually take advantage of riak shell scripts (e.g. riak, riak-admin, riak-repl) which can 
require sudoing to the riak user. If this is the case, you'll need to give the nagios user that right.

On ubuntu, that means adding the following to /etc/sudoers: `nagios  ALL=(riak) NOPASSWD: ALL`

#### NRPE
NRPE can be tricky when combined with escripts. The bottom line is that `escript` is meant to be run in a shell, but NRPE
doesn't execute in a shell. `escript` expects a `HOME` environment variable, which doesn't exist and produces an error 
that is not easily debugged: `NRPE: Unable to read output`.

To compensate for this, we added the `ebin/check_riak` script, which sets expected environment variables before executing 
the escript. It also has the benefit of making the `/etc/nagios/nrpe.cfg` easier to read.

##### Configuring NRPE
Speaking of `/etc/nagios/nrpe.cfg`, here's the kind of stuff you need to put in there.

```
command[check_riak_up]=riak-nagios up 
command[check_riak_repl_to_remote_site]=riak-nagios repl-server remote_site-on-local_site
command[check_riak_repl_from_remote_site]=riak-nagios repl-client local_site-on-remote_site
```

After any change to this file, you'll need to restart the nrpe server. On ubuntu, that's as easy as `service nagios-nrpe-server restart`

##### Testing NRPE
Once it's configured, you can use this nrpe plugin to test. If you see any of the possible status messages, and not the 
`NRPE: Unable to read output` error, your nrpe monitors are working.

```
/usr/lib/nagios/plugins/check_nrpe -H 127.0.0.1 -c check_riak_up
/usr/lib/nagios/plugins/check_nrpe -H 127.0.0.1 -c check_riak_repl_to_remote_site
/usr/lib/nagios/plugins/check_nrpe -H 127.0.0.1 -c check_riak_repl_from_remote_site
```

## Response
#### check_riak_up 
If this alert fires a critical alert, then riak on that node needs to be restarted by signing in and running `riak start`. If the node continues to crash, open a ticket with Basho

#### check_riak_repl_to
If this server side alert fires critical, there is an issue connecting to the client site, and you should open a ticket with basho
If this alert fires a warning, there were too many replication processes running, but we were able to kill the extra ones automatically and no action is required on your part

#### check_riak_repl_from
If this alert fires critical, the replication client cannot communicate with the replication server and you should open a ticket with Basho.
