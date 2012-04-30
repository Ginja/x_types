# Provider: x_computergroup
# Created: Mon Nov 28 10:38:36 PST 2011

begin
  require 'pp'
  require 'osx/cocoa'
  include OSX
rescue LoadError
  puts "Does not compute. Does not compute. Does not compute."
end

Puppet::Type.type(:x_computergroup).provide(:x_computergroup) do
  desc "Provides dscl interface for managing Mac OS X computer groups."

  commands  :dsclcmd          => "/usr/bin/dscl"
  commands  :uuidgen          => "/usr/bin/uuidgen"
  confine   :operatingsystem  => :darwin

  @@req_attrib_map_computergroup = { 
    'name'      => :name,
    'realname'  => :name,
    'gid'       => :gid,
  }
  
  def create    
    # Fix the existing record or create it as required
    if @computergroup
      guid = @computergroup['generateduid'].to_s
      raise if guid.nil? or guid.empty?
      unless @needs_repair.empty? or @needs_repair.nil?
        info("Repairing computer group: #{resource[:name]}")
        @needs_repair.each do |attrib|
          dsclcmd "/Local/#{resource[:dslocal_node]}", "-create", "/ComputerGroups/#{resource[:name]}", "#{attrib}", "#{resource[@@req_attrib_map_computergroup[attrib]]}"
        end
      end
    else
      info("Creating computer group: #{resource[:name]}")
      dsclcmd "/Local/#{resource[:dslocal_node]}", "-create", "/ComputerGroups/#{resource[:name]}"
      @@req_attrib_map_computergroup.each do |key,value|
        value = resource[@@req_attrib_map_computergroup[key]]
        dsclcmd "/Local/#{resource[:dslocal_node]}", "-create", "/ComputerGroups/#{resource[:name]}", "#{key}", "#{value}"
      end
    end
    # Reload the computergroup
    # For some reason, DS does not sync immediately after making the changes above.
    # As a workaround, a simple dscl query will force DS to update.
    dsclcmd "/Local/#{resource[:dslocal_node]}", "-read", "/ComputerGroups/#{resource[:name]}"
    # Now load the plist
    @computergroup = get_computergroup(resource[:name]).to_ruby
    # Check the PrimaryGroupID, f there isn't one, create it
    unless @computergroup['gid']
      dsclcmd "/Local/#{resource[:dslocal_node]}", "-create", "/ComputerGroups/#{resource[:name]}", 'PrimaryGroupID', "#{@next_primarygid}"
    end
    # Re-interpret missing members
    @missing_computers        = compare_membership(@valid_computer_members.keys, @computergroup['groupmembers'], @all_computers)
    @missing_computergroups   = compare_membership(@valid_computergroup_members.keys, @computergroup['nestedgroups'], @all_computergroups)
    @unmanaged_computers      = compare_membership(@computergroup['groupmembers'], @valid_computer_members.keys, @all_computers)
    @unmanaged_computergroups = compare_membership(@computergroup['nestedgroups'], @valid_computergroup_members.keys, @all_computergroups)
    # Conform membership
    if resource[:autocratic]
      unless @unmanaged_computers.empty? and @unmanaged_computergroups.empty?
        op = '-delete'
        @unmanaged_computers.each       { |guid, name| member_computer_op(guid, name, op) }
        @unmanaged_computergroups.each  { |guid, name| nested_computergroup_op(guid, name, op) }
      end
    end
    unless @missing_computers.empty? and @missing_computergroups.empty?
      op = '-merge'
      @missing_computers.each       { |guid, name| member_computer_op(guid, name, op) }
      @missing_computergroups.each  { |guid, name| nested_computergroup_op(guid, name, op) }
    end
  end
  
  def destroy
    info("Destroying computer group: #{resource[:name]}")
    dsclcmd "/Local/#{resource[:dslocal_node]}", "-delete", "/ComputerGroups/#{resource[:name]}"
  end

  def exists?
    info("Checking computer group: #{resource[:name]}")
    @needs_repair = []
    @next_primarygid = next_gid
    # Map all computer and computergroup records
    @all_computers        = map_all_records_by_guid(:computers)
    @all_computergroups   = map_all_records_by_guid(:computergroups)
    # Validate the membership resources
    @valid_computer_members       = validate_members(resource[:computers], @all_computers)
    @valid_computergroup_members  = validate_members(resource[:computergroups], @all_computergroups)
    begin
      @computergroup = get_computergroup(resource[:name])
      if @computergroup
        @computergroup = @computergroup.to_ruby
        # Check the defined attributes
        @@req_attrib_map_computergroup.each do |key,value|
          @needs_repair << key unless @computergroup[key].to_s.eql?(resource[value])
          if @computergroup['gid'] and resource[:gid].to_s.empty?
            @needs_repair.delete('gid')
          end
        end
        @missing_computers        = compare_membership(@valid_computer_members.keys, @computergroup['groupmembers'], @all_computers)
        @missing_computergroups   = compare_membership(@valid_computergroup_members.keys, @computergroup['nestedgroups'], @all_computergroups)
        @unmanaged_computers      = compare_membership(@computergroup['groupmembers'], @valid_computer_members.keys, @all_computers)
        @unmanaged_computergroups = compare_membership(@computergroup['nestedgroups'], @valid_computergroup_members.keys, @all_computergroups)
        if resource[:autocratic]
          return unless @unmanaged_computers.empty? and @unmanaged_computergroups.empty?
        end
        return unless @missing_computers.empty? and @missing_computergroups.empty?
      else
        return false
      end
    rescue # => error
      # notice("Ruby Error: #{error.message}")
      return false
    end
    return @needs_repair.empty?
  end

  # Returns difference between 2 arrays, returns a hash mapping guid -> name
  # 3 args: 2 arrays of GUIDs, and a map that resolves GUID -> name
  def compare_membership(list_1, list_2, map)
    difference = {}
    guids = []
    unless list_1.nil?
      missing_records = list_1.to_a - list_2.to_a
      unless missing_records.empty?
        missing_records.each do |guid|
          difference[guid] = map[guid]
        end
      end
    end
    difference
  end
    
  # Validates the list of specified record names against all known records of :type
  # Generates a message if any of the defined records do not resolve or collide
  # Returns a hash that maps the record's guid => name
  def validate_members(members, all_records)
    valid_members = {}
    unless members.nil? or all_records.nil?
      names_to_guids  = all_records.invert
      # If inverting the hash produces a different length, you have a name collision
      # and DS should fail miserably anyway...
      if all_records.length == names_to_guids.length
        members.each do |member|
          if names_to_guids[member]
            valid_members[names_to_guids[member]] = member
          else
            notice("Error: #{member}, record not found. Cannot add unknown member to: #{resource[:name]}")
          end
        end
      end
    end
    valid_members
  end
  
  # Perform a computer add or delete
  def member_computer_op(guid, name, op)
    tag = 'Adding'
    tag = 'Removing' if op =~ /-delete/
    info("#{tag} computer member: #{name}")
    dsclcmd "/Local/#{resource[:dslocal_node]}", "#{op}", "/ComputerGroups/#{resource[:name]}", "GroupMembers", "#{guid}"
    dsclcmd "/Local/#{resource[:dslocal_node]}", "#{op}", "/ComputerGroups/#{resource[:name]}", "GroupMembership", "#{name}"
  end

  # Perfrom a computergroup add or delete
  def nested_computergroup_op(guid, name, op)
    tag = 'Adding'
    tag = 'Removing' if op =~ /-delete/
    info("#{tag} nested computergroup: #{name}")
    dsclcmd "/Local/#{resource[:dslocal_node]}", "#{op}", "/ComputerGroups/#{resource[:name]}", "NestedGroups", "#{guid}"
  end
  
  
  # Get all records of 'type' for the target node
  # arg is Symbol, :computers or :computergroups
  def map_all_records_by_guid(type)
    type = type.to_s
    map = {}
    begin
      all_records = `/usr/bin/dscl /Local/#{resource[:dslocal_node]} -list /#{type}`.split("\n")
      unless all_records.empty?
        all_records.each do |record|
          guid = `/usr/bin/dscl /Local/#{resource[:dslocal_node]} -read /#{type}/#{record} GeneratedUID`.split[1].chomp
          map[guid] = record
        end
      end
    rescue => error
      notice("Error returning #{type.to_s} records: #{error.message}")
    end
    map    
  end
  
  # Get the next available PrimaryGroupID number as String
  def next_gid
    min = 1025
    begin
      all_records = `/usr/bin/dscl /Local/#{resource[:dslocal_node]} -list /ComputerGroups`.split("\n")
      gids =[]
      unless all_records.empty?
        all_records.each do |record|
          gid = `/usr/bin/dscl /Local/#{resource[:dslocal_node]} -read /ComputerGroups/#{record} PrimaryGroupID`.split[1].chomp
          gids << gid.to_i
        end
        gids.sort!.uniq!
        gids.each_with_index do |gid, i|
          next if (gid < min)
          next if (gid + 1 == gids[i + 1])
          return gid + 1
        end
      end
    rescue => error
      puts "Ruby Error: #{error.message}"
    end
    min.to_s
  end
  
  # Not implemented
  # def purge_orphaned_records    
  # end

  # Load the computergroup data
  ## Returns an NSDictionary representation of the the computergroup.plist if it exists
  ## If it doesn't, it will return nil
  def get_computergroup(name)
    @file = "/private/var/db/dslocal/nodes//#{resource[:dslocal_node]}/computergroups/#{name}.plist"
    computergroup = NSMutableDictionary.dictionaryWithContentsOfFile(@file)
  end

end
