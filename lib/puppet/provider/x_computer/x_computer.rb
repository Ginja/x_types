# Provider: x_computer
# Created: Mon Dec  5 12:19:52 PST 2011

begin
  require 'pp'
  require 'osx/cocoa'
  include OSX
rescue LoadError
  puts "What are you doing, Dave? This is highly irregular."
end

Puppet::Type.type(:x_computer).provide(:x_computer) do
  desc "Provides dscl interface for managing Mac OS X computers."

  commands  :dsclcmd          => "/usr/bin/dscl"
  commands  :uuidgen          => "/usr/bin/uuidgen"
  confine   :operatingsystem  => :darwin

  @@req_attrib_map_computer = { 'dsAttrTypeStandard:RecordName' => :name,
    'dsAttrTypeStandard:RealName'     => :name,
    'dsAttrTypeStandard:ENetAddress'  => :en_address,
    'dsAttrTypeStandard:HardwareUUID' => :hardware_uuid
  }

  def create
    # Records with a HardwareUUID or ENetAddress that matches the resource spec will be destroyed
    if @dupes
      unless @dupes.empty?
        @dupes.each do |dupe|
          info("Removing duplicate computer record: #{dupe}")
          dsclcmd "/Local/#{resource[:dslocal_node]}", "-delete", "/Computers/#{dupe}"
        end
      end
    end
    info("Creating computer record: #{resource[:name]}")
    guid = uuidgen.chomp
    if @computer
      guid = @computer['dsAttrTypeStandard:GeneratedUID'].to_s
      raise if guid.nil? or guid.empty?
      @needs_repair.each do |attrib|
        dsclcmd "/Local/#{resource[:dslocal_node]}", "-merge", "/Computers/#{resource[:name]}", "#{attrib}", "#{resource[@@req_attrib_map_computer[attrib]]}"
      end
    else
      dsclcmd "/Local/#{resource[:dslocal_node]}", "-create", "/Computers/#{resource[:name]}"
      @@req_attrib_map_computer.each do |key,value|
        dsclcmd "/Local/#{resource[:dslocal_node]}", "-merge", "/Computers/#{resource[:name]}", "#{key}", "#{resource[@@req_attrib_map_computer[key]]}"
      end
    end
  end

  def destroy
    info("Destroying computer record: #{resource[:name]}")
    dsclcmd "/Local/#{resource[:dslocal_node]}", "-delete", "/Computers/#{resource[:name]}"
  end

  def exists?
    info("Checking computer record: #{resource[:name]}")
    # Leopard does nto allow HardwareUUID computer record attribute 
    @kernel_version_major = Facter.kernelmajversion.to_i
    @@req_attrib_map_computer.delete('dsAttrTypeStandard:HardwareUUID') if @kernel_version_major == 9
    @needs_repair = []
    @dupes = find_duplicate_records
    @computer = get_computer(resource[:name])
    if @computer
      @@req_attrib_map_computer.each do |key,value|
        @needs_repair << key unless @computer[key].to_s.eql?(resource[value])
      end
      return false unless @needs_repair.empty?
    else
      return false
    end
    return @dupes.empty?
  end

  # Find comptuer records with duplicate HardwareUUIDs or ENetAddress
  def find_duplicate_records
    unique_attribs = ['dsAttrTypeStandard:ENetAddress', 'dsAttrTypeStandard:HardwareUUID']
    unique_attribs.delete('dsAttrTypeStandard:HardwareUUID') if @kernel_version_major == 9
    all_computers = `/usr/bin/dscl /Local/#{resource[:dslocal_node]} -list /Computers`.split("\n")
    all_computers.reject! { |r| r.eql?("#{resource[:name]}") }
    duplicate_records = []
    all_computers.each do |record|
      unique_attribs.each do |attrib|
        string = `/usr/bin/dscl /Local/MCX -read /Computers/#{record} #{attrib} 2> /dev/null`
        unless string.nil?
          value = string.split[1]
          duplicate_records << record if value =~ /#{resource[@@req_attrib_map_computer[attrib]]}/
        end
      end
    end
    duplicate_records.uniq
  end

  # Returns a hash of computer properties
  def get_computer(name)
    string = `dscl -plist /Local/#{resource[:dslocal_node]} -read /Computers/#{name} 2> /dev/null`.to_ns
    return false if string.empty? or string.nil?
    data = string.dataUsingEncoding(OSX::NSUTF8StringEncoding)
    dict = OSX::NSPropertyListSerialization.objc_send(
      :propertyListFromData, data,
      :mutabilityOption, OSX::NSPropertyListMutableContainersAndLeaves,
      :format, nil,
      :errorDescription, nil
    )
    return false if dict.nil?
    dict.to_ruby
  end

end
