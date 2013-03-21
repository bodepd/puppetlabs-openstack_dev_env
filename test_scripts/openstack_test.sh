#!/bin/bash
#
# script to build a two node openstack environment and test.
# this script is intended to be run as a jenkins parameterized build with
# the following build parameters:
#   $operatingsystem - OS to test OS install on (accepts Redhat/Ubuntu)
#   $openstack_version - openstack version to test (accepts folsom/grizzly)
#   $test_mode type of test to run (accepts: tempest_full, tempest_smoke, puppet_openstack, unit)
#   $module_install_method - how to install modules (accepts librarian or pmt)
#
# # I am running it as follows:
# mkdir $BUILD_ID
# cd $BUILD_ID
# git clone git://github.com/puppetlabs/puppetlabs-openstack_dev_env
# cd puppetlabs-openstack_dev_env
# bash test_scripts/openstack_test.sh
# TODO figure out if I should add pull request support
set -e
set -u

# install required modules
if [ $module_install_method = 'librarian' ]; then
  bundle exec librarian-puppet install
elif [ $module_install_method = 'pmt' ]; then
  puppet module install --modulepath=`pwd`/modules  puppetlabs-openstack
  git clone https://github.com/ripienaar/hiera-puppet modules/hiera_puppet
  git clone git://github.com/puppetlabs/puppetlabs-swift modules/swift
  git clone git://github.com/puppetlabs/puppetlabs-tempest modules/tempest
  git clone git://github.com/puppetlabs/puppetlabs-vcsrepo modules/vcsrepo
fi
# install a controller and compute instance

# only build out integration test environment if we are not running unit tests
if [ ! $test_mode = 'unit' ]; then
  # set operatingsystem to use for integration tests tests
  echo "operatingsystem: ${operatingsystem}" > config.yaml
  if [ $openstack_version = 'grizzly' ]; then
    echo 'openstack_version: grizzly' > hiera_data/jenkins.yaml
  else
    echo 'openstack_version: folsom' > hiera_data/jenkins.yaml
  fi

  # install gem dependencies
  mkdir .vendor
  export GEM_HOME=`pwd`/.vendor
  # install gem dependencies
  bundle install

  # check that the VM is not currently running
  # if it is, stop that VM
  if VBoxManage list vms | grep openstack_controller.puppetlabs.lan; then
    VBoxManage controlvm openstack_controller.puppetlabs.lan  poweroff || true
    VBoxManage unregistervm openstack_controller.puppetlabs.lan  --delete
  fi
  bundle exec vagrant up openstack_controller

  # check if the compute VM is running, if so stop the VM before launching ours
  if VBoxManage list vms | grep compute2.puppetlabs.lan; then
    VBoxManage controlvm compute2.puppetlabs.lan  poweroff || true
     VBoxManage unregistervm compute2.puppetlabs.lan --delete
  fi
  bundle exec vagrant up compute2
  # install tempest on the controller
  bundle exec vagrant status
fi

if [ $test_mode = 'puppet_openstack' ]; then
  # run my simple puppet integration tests
  bundle exec vagrant ssh -c 'sudo bash /tmp/test_nova.sh;exit $?' openstack_controller
elif [ $test_mode = 'tempest_smoke' ]; then
  # run the tempest smoke tests
  bundle exec vagrant ssh -c 'sudo puppet apply --certname tempest --modulepath=/etc/puppet/modules-0/ /etc/puppet/manifests/site.pp --trace --debug' openstack_controller
  # run tempest tests
  bundle exec vagrant ssh -c 'cd /var/lib/tempest/;sudo ./jenkins_launch_script.sh --smoke;' openstack_controller
elif [ $test_mode = 'tempest_full' ]; then
  bundle exec vagrant ssh -c 'cd /var/lib/tempest/;sudo ./jenkins_launch_script.sh;' openstack_controller
elif [ $test_mode = 'unit' ]; then
  echo 'we do not yet support running unit tests'
else
  echo "Unsupported testnode ${test_mode}, this test matrix only support tempest_smoke and puppet_openstack tests"
fi
