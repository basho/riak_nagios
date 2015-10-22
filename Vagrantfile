# -*- mode: ruby -*-
# vi: set ft=ruby :

# Vagrant file to test riak_nagios plugin

Vagrant.configure(2) do |config|
  config.vm.box = "phusion/ubuntu-14.04-amd64"
  config.vm.provision "shell", inline: <<-SHELL
apt-get update
apt-get install -y curl git erlang
curl -s https://packagecloud.io/install/repositories/basho/riak/script.deb.sh | bash
apt-get install -y riak
echo "ulimit -n 65536" > /etc/default/riak
perl -pi -e 's/^storage_backend =.*/storage_backend = leveldb/' /etc/riak/riak.conf
service riak start
( cd /root ; git clone https://github.com/basho/riak_nagios.git ; cd riak_nagios ; make escript )
cp /root/riak_nagios/check_node /usr/sbin/check_node
apt-get install -y nagios-nrpe-server
apt-get install -y --force-yes --no-install-recommends -f nagios-nrpe-plugin
cp /vagrant/nrpe-riak.cfg /etc/nagios/nrpe.d/nrpe-riak.cfg
service nagios-nrpe-server restart
riak-admin wait-for-service riak_kv
/usr/lib/nagios/plugins/check_nrpe -H 127.0.0.1 -c node_up
/usr/lib/nagios/plugins/check_nrpe -H 127.0.0.1 -c riak_kv_up
/usr/lib/nagios/plugins/check_nrpe -H 127.0.0.1 -c file_handle_count
/usr/lib/nagios/plugins/check_nrpe -H 127.0.0.1 -c leveldb_compaction
/usr/lib/nagios/plugins/check_nrpe -H 127.0.0.1 -c riak_repl

  SHELL
end
