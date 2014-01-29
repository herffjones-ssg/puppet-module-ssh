# == Class: ssh
#
# Manage ssh client and server
#
# == Parameters:
#
#  $permit_root_login: defaults to 'no',
#   valid values = yes/without-password/forced-commands-only/no
#
class ssh (
  $packages                = ['openssh-server',
                              'openssh-server',
                              'openssh-clients'],
  $permit_root_login       = 'no',
  $x11_forwarding          = 'no',
  $purge_keys              = 'true',
  $manage_firewall         = true,
  $ssh_config_path         = '/etc/ssh/ssh_config',
  $ssh_config_owner        = 'root',
  $ssh_config_group        = 'root',
  $ssh_config_mode         = '0644',
  $sshd_config_path        = '/etc/ssh/sshd_config',
  $sshd_config_owner       = 'root',
  $sshd_config_group       = 'root',
  $sshd_config_mode        = '0600',
  $service_ensure          = 'running',
  $service_name            = 'sshd',
  $service_enable          = 'true',
  $service_hasrestart      = 'true',
  $service_hasstatus       = 'true',
  $ssh_key_ensure          = 'present',
  $ssh_key_type            = 'ssh-rsa',
  $manage_root_ssh_config  = 'false',
  $root_ssh_config_content = "# This file is being maintained by Puppet.\n# DO NOT EDIT\n",
) {
  include nagios

  case $permit_root_login {
    'no', 'yes', 'without-password', 'forced-commands-only': {
      # noop
    }
    default: {
      fail("permit_root_login may be either 'yes', 'without-password', 'forced-commands-only' or 'no' and is set to ${permit_root_login}")
    }
  }

  case $ssh_key_type {
    'ssh-rsa','rsa': {
      $key = $::sshrsakey
    }
    'ssh-dsa','dsa': {
      $key = $::sshdsakey
    }
    default: {
      fail("ssh_key_type must be 'ssh-rsa', 'rsa', 'ssh-dsa', or 'dsa' and is ${ssh_key_type}")
    }
  }

  case $purge_keys {
    'true','false': {
      # noop
    }
    default: {
      fail("purge_keys must be 'true' or 'false' and is ${purge_keys}")
    }
  }

  package { 'ssh_packages':
    ensure => installed,
    name   => $packages,
  }

  file  { 'ssh_config' :
    ensure  => file,
    path    => $ssh_config_path,
    owner   => $ssh_config_owner,
    group   => $ssh_config_group,
    mode    => $ssh_config_mode,
    content => template('ssh/ssh_config.erb'),
    require => Package['ssh_packages'],
  }

  file  { 'sshd_config' :
    ensure  => file,
    path    => $sshd_config_path,
    mode    => $sshd_config_mode,
    owner   => $sshd_config_owner,
    group   => $sshd_config_group,
    content => template('ssh/sshd_config.erb'),
    require => Package['ssh_packages'],
  }

  case $manage_root_ssh_config {
    'true': {

      include common

      #common::mkdir_p { "${::root_home}/.ssh": }

      #file { 'root_ssh_dir':
      #  ensure  => directory,
      #  path    => "${::root_home}/.ssh",
      #  owner   => 'root',
      #  group   => 'root',
      #  mode    => '0700',
      #  require => Common::Mkdir_p["${::root_home}/.ssh"],
      #}

      file { 'root_ssh_config':
        ensure  => file,
        path    => "${::root_home}/.ssh/config",
        content => $root_ssh_config_content,
        owner   => 'root',
        group   => 'root',
        mode    => '0600',
      }
    }
    'false': {
      # noop
    }
    default: {
      fail("manage_root_ssh_config is <${manage_root_ssh_config}> and must be \'true\' or \'false\'.")
    }
  }

  service { 'sshd_service' :
    ensure     => $service_ensure,
    name       => $service_name,
    enable     => $service_enable,
    hasrestart => $service_hasrestart,
    hasstatus  => $service_hasstatus,
    subscribe  => File['sshd_config'],
  }

  if $manage_firewall == true {
    firewall { '22 open port 22 for SSH':
      action => 'accept',
      dport  => 22,
      proto  => 'tcp',
    }
  }

  # Include partial hostname 'app1.site' in hosts like 'app1.site.company.com'.
  $partial_hostname = regsubst($fqdn, '\.herffjones\.hj-int$', '')
  if $partial_hostname == $hostname {
    $host_aliases = [ $ipaddress, $hostname, "${fqdn}." ]
  } else {
    $host_aliases = [ $ipaddress, $hostname, $partial_hostname, "${fqdn}." ]
  }

  # export each node's ssh key
  @@sshkey { $::fqdn :
    ensure  => $ssh_key_ensure,
    host_aliases => $host_aliases,
    type    => $ssh_key_type,
    key     => $key,
    require => Package['ssh_packages'],
  }

  # SSH Key for ssgsvn.herffjones.hj-int
  sshkey { 'ssgsvn.herffjones.hj-int':
      ensure => 'present',
      type   => 'rsa',
      key    => 'AAAAB3NzaC1yc2EAAAABIwAAAQEArm8ij1MFfI3yZLo+5l8GlY82i5nBODa9332XgonV5J9FlxLL3Xqs82+EsYbncZhEF1TEF/gB/uXGc62rbkyOGIfJR6fKk2mA+Ix7f6LuowSwrRHvLgDY+lLnUMZPuEpsX0AdJvyFBHYZkoq9wd0DP2exXX9ZMZ7iRmBQBrrpDLrbCEiCOi9n/wMgxsJVUvuXyMF6URBn3BnxPYTQnL0Kh8so2AvwbH2w8ulKQ+QXzX6P+Xf6fPg4BszKLPFPkwFWLrO5rhiORWLzkVFnTrlSimco+KMExfpG4GzRFVSJzFfPDSQVByfoveiTFA5+UMwAEyNWhlFtwJBpa29k4K6OBw==',
  }

  # import all nodes' ssh keys
  if $nagios::master == "true" {
    #  We're doing this in the Nagios module so we can update enteprise as well.
  } else {
    Sshkey <<||>>
  }

  # remove ssh key's not managed by puppet
  resources  { 'sshkey':
    purge => $purge_keys,
  }
}
