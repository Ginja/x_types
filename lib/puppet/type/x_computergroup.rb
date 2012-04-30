# Type: x_computergroup
# Created: Mon Nov 28 09:52:24 PST 2011

Puppet::Type.newtype(:x_computergroup) do
  @doc = "Manage Mac OS X ComputerGroup objects
    x_computergroup { 'mynewgroup':
      dslocal_node    => 'MyNode'
      computers       => 'thiscomputer',
      computergroups  => ['group1','group2','group3'],
      gid             => '5000',
      autocratic      => 'true',
      ensure          => present
    }"

  ensurable

  newparam(:name) do
    desc "The name of the group to manage."
    isnamevar
  end

  newparam(:dslocal_node) do
    desc "The name of the node to manage."
    defaultto 'Default'
  end

  newparam(:computers) do
    desc "An array containing a list of computers to add to the designated group."
    munge do |value|
      value.to_a
    end
  end

  newparam(:computergroups) do
    desc "An array containing a list of computergroups to nest in the designated group."
    munge do |value|
      value.to_a
    end
  end

  newparam(:gid) do
    desc "Numeric group identifier assigned to the computer group. (optional)
          GIDs can be assigned automatically based on the available pool. GIDs
          selected will always be 1025 or greater."
    munge do |value|
      value.to_s
    end    
  end

  newparam(:autocratic) do
    desc "Setting this to true will explicitly define which records are members of the target computer group. This
          means that any record not defined in the :computers or :compuregroups array will be removed if present."
    newvalues(true, false, :enable, :enabled, :disable, :disabled)
    defaultto false
  end
  
end
