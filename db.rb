DataMapper::Model.raise_on_save_failure = true  # globally across all models

class User
  include DataMapper::Resource
  include BCrypt

  property :id,         Serial,      :key => true
  property :username,   String,      :length => 4..64
  property :password,   BCryptHash
  property :isAdmin,    Boolean,     :default => false
  property :created_at, DateTime
  property :updated_at, DateTime

  def authenticate(pass)
    self.password == pass ? true : false
  end
end


class Sample
  include DataMapper::Resource

  property :id,         Serial
  property :sampleID,   String,   :required => true
  property :attribs,    Json
  property :status,     String,   :default => "Good"  # [Empty, Unknown, Good, Bad, Used, etc...]
  property :volume,     Float,    :required => false
  property :created_at, DateTime
  property :updated_at, DateTime

  has n, :wells
  has n, :plate, :through => :wells

  def original_well
    self.wells.each do |well|
      if well.isOriginal
        return well
      end
    end
  end

  # In a simple mapping, a sample is either present in just the original well or the mapped well
  # This function will return the orignal well if unmapped (or mapped and uncomplete) or the mapped well (after batch is complete)
  def well
    if self.wells.count == 1
      return self.wells.first
    elsif self.wells.count == 2
      self.wells.each do |well|
        if not well.isOriginal
          return well
        end
      end
    else
      raise "Trying to access sample well in non standard multiwell context (this sample is linked to more than 2 wells)."
    end
  end

  def name
    return self.sampleID
  end


  def claimed_volume()
    return Mapping.all(:provider => self.well).map{|x| x.volume}.inject(:+)
  end

end


class Coding
  include DataMapper::Resource

  property :id,         Serial
  property :attrib,     String
  property :code,       String,   :required => false
  property :value,      String,   :required => false
  property :typeGuess,  String
  property :created_at, DateTime
  property :updated_at, DateTime

end


class Well
  include DataMapper::Resource

  property :id,         Serial
  property :row,        String
  property :col,        Integer
  property :status,     String,   :default => "Empty" # [Empty, Used, Unknown, etc...]
  property :isOriginal, Boolean,  :default => false   # Should be set to true when first loading the database
  property :created_at, DateTime
  property :updated_at, DateTime

  # This are the valid options for a 96 well plate
  validates_within :row,  :set => ['A','B','C','D','E','F','G','H']
  validates_within :col,  :set => 1..12

  belongs_to  :plate
  belongs_to  :sample, :required => false


  ## This code was used to have multiple potental mappings to each well
  ## This has been disabled to avoid sample mixing and to enforce the prefered method
  ##   of updating batch files to reflect updated mappings
  ## A well mapping defines potential mappings of source to destination wells (also see load_batch)
  #class Association
  # include DataMapper::Resource
  # storage_names[:default] = 'well_associations'
  # belongs_to :sourcee, 'Well', :key => true
  # belongs_to :sourcer, 'Well', :key => true
  #end
  ## These set up potential mappings of source to destination wells through the Mappings subclass
  ## This mapping is interfaced with destination_wells and source wells
  #has n, :association_with_sourcer_wells, 'Well::Association', :child_key => [ :sourcee_id ], :constraint => :destroy
  #has n, :association_with_sourcee_wells, 'Well::Association', :child_key => [ :sourcer_id ], :constraint => :destroy
  #has n, :destination_wells, self, :through => :association_with_sourcer_wells, :via => :sourcer
  #has n, :source_wells, self, :through => :association_with_sourcee_wells, :via => :sourcee

  # Convenience functions for giving the well name
  def name(leading_zero: false)
    if leading_zero
      self.long()
    else
      self.short()
    end
  end
  # Gives well name like A1
  def short(leading_zero: false)
    return "#{self.row}#{self.col}"
  end
  # Gives well name using leading zero like A01
  def long
    if self.col < 10
      return "#{self.row}0#{self.col}"
    else
      return "#{self.row}#{self.col}"
    end
  end

  def location
    return "#{self.plate.plateID}_#{self.row}#{self.col}"
  end

  # Whether a well is considered usable. Other criterion can be added here
  def usable?
    return self.sample.status=="Good"
  end

  def provider(as_text: false)
    provider = Mapping.first(:destination => self)
    if provider.nil?
      return nil
    else
      provider = provider.provider
    end
    if as_text
      return "#{provider.plate.plateID}: #{provider.short}"
    end
    return provider
  end

  def destination(as_text: false)
    destination = Mapping.all(:provider => self)
    if destination.count == 0
      return nil
    elsif destination.count > 1
      return destination.map{|x| "#{x.destination.plate.plateID}: #{x.destination.short}"}  if as_text
      return destination.map{|x| x.destination}
    else
      return "#{destination.first.destination.plate.plateID}: #{destination.first.destination.short}" if as_text
      return destination.first.destination
    end
  end

  before :save do
    existing_well = self.plate.wells.first(:row => self.row, :col => self.col)
    next if existing_well.nil?
    if (existing_well != self)
      raise "You cannot create duplicate wells on a single plate (or duplicate wells were detected)."
    end
  end
end


class Plate
  include DataMapper::Resource

  property :id,           Serial
  property :plateID,      String,   :required => true
  property :type,         String,   :default => "Source"  # [Source, Destination, Control, etc...]
  property :batchCreated, Boolean,  :default => false
  property :created_at,   DateTime
  property :updated_at,   DateTime

  has n, :wells, :constraint => :destroy
  has n, :samples, :through => :wells
  has n, :pods

  def name
    return self.plateID
  end

  def isComplete
    Mapping.all(:destination => self.wells).map{|x| x.isComplete}.all?
  end
end


# This class sets up the actual mappings used in a batch
class Mapping
  include DataMapper::Resource

  property :id,         Serial
  property :volume,     Float
  property :isComplete, Boolean, :default => false
  property :created_at, DateTime
  property :updated_at, DateTime

  belongs_to :provider,    'Well', :key => true
  belongs_to :destination, 'Well', :key => true
  belongs_to :batch, :required => false
end


class Batch
  include DataMapper::Resource

  property :id,         Serial
  property :batchID,    String
  property :isComplete, Boolean,  :default => false
  property :created_at, DateTime
  property :updated_at, DateTime

  has n, :pods,     :constraint => :destroy
  has n, :mappings, :constraint => :destroy

  def plates()
    return self.pods.plates
  end

  def samples()
    if self.isComplete
      return self.mappings.destination.samples.uniq
    else
      return self.mappings.provider.samples.uniq
    end
  end

  def complete!()
    # Don't repeat if this plate has been already marked as complete
    return if self.isComplete
    # For each mapping, link the providing well's sample to the destination well
    self.mappings.each do |mapping|
      provider    = mapping.provider
      destination = mapping.destination
      sample      = provider.sample

      # Copy the sample
      destination.sample = Sample.create(provider.sample.attributes.merge(:id => nil))
      destination.status = "Used"

      # Update volumes if present
      if not provider.sample.volume.nil?
        prodiver.sample.volume -= mapping.volume
        destination.sample.volume = mapping.volume
        provider.sample.save!
        destination.sample.save!
      end

      destination.save!
      provider.save!
      mapping.update!(:isComplete => true)
      #mapping.provider.status = "Empty"
      #provider.save!
    end

    self.update!(:isComplete => true)
    return true
  end

  def self.upto(name)
    whereat = Batch.all(:order => [:created_at]).map(&:batchID).index(name)
    return nil if whereat.nil?
    return Batch.all(:order => [:created_at])[0..whereat]
  end

  def name
    return self.batchID
  end
end

class Pod
  include DataMapper::Resource
  property :id,         Serial
  property :position,   Integer   # [4-12], Pod positions may vary depending on setup!
  property :type,       String
  property :created_at, DateTime
  property :updated_at, DateTime

  belongs_to :batch
  belongs_to :plate, :required => false      # A pod doesn't have to have a plate
  validates_within :position, :set => 4..12  # But it does need a position!

  # This should change too depending on specific setups
  before :save do
    if self.position < 4 or self.position > 12
      puts "Pod position must be between 4 and 12 (inclusive)"
      next
    end
    # Uses default layout of column 1&2 => Source, column 3 row 1 => Control, and column 3 row 2&3 => Destination
    self.type = [6.times.collect {"Source"}, "Control", 2.times.collect {"Destination"}].flatten[self.position-4]
  end
end







### Database associated functions
# Split the well name into row/columns ("A01" => [A,1] or "A1" to [A,1])
def split_well(well_name)
  j, row, col = well_name.split(/^([A-H])(0?[1-9]|[1][0-2])$/)
  return [row, col.to_i]
end

# Given a plate and a well name, will return the corresponding sample
def lookup_sample(plate, well_name)
  row,col = split_well(well_name)
  plate = Plate.first(:plateID => plate)
  well = plate.wells.first(:row => row, :col => col.to_i)
  well.sample
end

# Given a plate and a well name, will return the corresponding well
def lookup_well(plate, well_name)
  row,col = split_well(well_name)
  plate = Plate.first(:plateID => plate)
  well = plate.wells.first(:row => row, :col => col.to_i)
end

# Resets the database
def reset_database()
  DataMapper.auto_migrate!
  # Remove other files?
end



### DECODING
# This function is used to guess the type of a list of values
# It optionally takes a previous type guess ["boolean", "int", "float", "string"]
# and will relax the guess if the previous guess was more general (eg. previous guess of string is more general than an integer)
def type_guess(values, previous:nil)
  # Test for the type
  if not values.to_set.map{|x| (x.to_s =~ /(?=true)|(?=false)/i).nil?}.any?
    t = "boolean"
  elsif not values.to_set.map{|x| (Integer(x) rescue nil).nil?}.any?
    t = "integer"
  elsif not values.to_set.map{|x| (Float(x) rescue nil).nil?}.any?
    t = "float"
  else
    t = "string"
  end

  # Relaxes the type guess if a previous type is more general
  if not previous.nil?
    if t==previous
      t = previous # Sort of useless, but good to be explicit
    elsif t=="string" or previous=="string"
      t = "string"
    elsif previous == "boolean" and (t == "float" or t == "integer")
      if values.map {|x| Integer(x)}.to_set.subset? [0,1].to_set
        t = previous # Don't relax if we have 0s or 1s
      else
        t = t # Again...
      end
    elsif (previous == "integer" or previous == "float") and t == "boolean"
      t = previous
    elsif t == "float" and previous == "integer"
      t = "float"
    elsif t == "integer" and previous == "float"
      t = "float"
    end
  end

  return t
end


# Does actual decoding on a element by element basis
def decode(attrib, code)
  record = Coding.first(attrib: attrib, code: code)
  if record.nil?
    record = Coding.first(attrib: attrib)
    if record.nil?
      return code
    end
    value = code
  else  # Has a direct mapping
    value = record.value
  end

  # Decode the value by type
  if record.typeGuess == "boolean" and (["false",false,"0",0].include? value)
    new_val = false
  elsif record.typeGuess == "boolean" and (["true",true,"1",1].include? value)
    new_val = true
  elsif record.typeGuess == "integer"
    new_val = Integer(value)
  elsif record.typeGuess == "float"
    new_val = Float(value)
  else
    new_val = value
  end

  return new_val
end



###############################


# This function is used to check if the column headers of a coding file are correct to parse into the database
# Since this file is small and easily parsed on the fly, this function will also add it to the database
# Input:
#     if_:        The input file path
#     attribs:    The attributes from the datafile
#     opts:       Passed to CSV
#     just_check: Simply see if the file looks OK
#     web_mode:   Whether to run in web mode or not (for web layer message passing)
# Output:
#     Will return ['Good!', {attrib => type}] or ['Error', (error message)] depending on validity of the input file
#     Will also populate the Coding table with entries
def add_coding(if_:nil, attribs:nil, opts:{:headers => true, :col_sep => "\t"}, just_check:false, web_mode:false)
  require 'csv'

  puts "Processing..." if not web_mode

  if if_.nil?
    msg = "No file specified."
    web_mode ? (return ["Error", msg]) : (puts msg)
  end

  if attribs.nil?
    msg = "No attributes were specified. If no coding is used, just skip this step."
    web_mode ? (return ["Error", msg]) : (puts msg)
  end

  # Figure out headers
  begin
    headers = CSV.read(if_,opts)[0].headers
  rescue
    msg = "Unable to read the header. Is this file tab-delimited?"
    web_mode ? (return ["Error", msg]) : (puts msg)
  end

  # Check column headers
  if not headers.to_set==["Attribute", "Value", "Code"].to_set
    msg = "Coding file must be tab-delimited with column headers 'Attribute', 'Value', 'Code'."
    web_mode ? (return ["Error", msg]) : (puts msg)
  end

  # Process the file
  begin
    entries = CSV.read(if_,opts)
  rescue
    msg = "Unable to read the input file!"
    web_mode ? (return ["Error", msg]) : (puts msg)
  end

  mapping = {}
  entry_no = 0
  # For each entry in the database flat file
  entries.each do |entry|
    entry_no += 1

    # Get fields
    attrib = entry['Attribute']
    value  = entry['Value']
    code   = entry['Code']

    if attrib.nil? or value.nil? or code.nil?
      msg = "In consistent format with entry number: #{entry_no}."
      web_mode ? (return ["Error", msg]) : (puts msg)
    end

    # Check that the attribute is legitimate
    if not attribs.include? attrib
      msg = "In consistent attribute name with entry number: #{entry_no}."
      web_mode ? (return ["Error", msg]) : (puts msg)
    end

    # Check that the code is unique
    if not mapping[attrib].nil? and not mapping[attrib][code].nil?
      msg = "Attempted to redefine an attribute code with entry number: #{entry_no}."
      web_mode ? (return ["Error", msg]) : (puts msg)
    end


    (mapping[attrib] ||= {}).store(code,value)
  end

  for key in mapping.keys
    foo = mapping[key]
    t = type_guess(foo.values)

    next if just_check
    # Otherwise store the coding
    foo.each do |code, value|
      Coding.create!(:attrib    => key,
                    :code       => code,
                    :value      => value,
                    :typeGuess  => t)
    end

  end

  return ["Good!",""]
end



# This function is used to check if the column headers of a data file are correct to parse into the database
# Input:
#     if_:      The input file path
#     opts:     Passed to CSV
# Output:
#     Will return ['Good!', (non-required header names)] or ['Error', (error message)] depending on validity of the input file
def check_db_file(if_:nil,  opts:{:headers => true, :col_sep => "\t"})
  require 'csv'

  if if_.nil?
    return ["Error","No file specified."]
  end

  # Figure out headers
  begin
    headers = CSV.read(if_,opts)[0].headers
  rescue
    return ["Error","Unable to read the header. Is this file tab-delimited?"]
  end

  # Define column headers
  samp_h, plate_h, well_h = [nil,nil,nil]
  # Get matched column names
  headers.each { |head| head =~ /sample.*id/i? samp_h  = head : nil }
  headers.each { |head| head =~ /plate.*id/i?  plate_h = head : nil }
  headers.each { |head| head =~ /well/i?       well_h  = head : nil }
  if samp_h==plate_h || samp_h==well_h || plate_h==well_h
    return ["Error","Confusing column headers. Is this file tab-delimited?"]
  elsif samp_h.nil?
    return ["Error","Could not find a column labeled 'SampleID'"]
  elsif plate_h.nil?
    return ["Error","Could not find a column labeled 'PlateID'"]
  elsif well_h.nil?
    return ["Error","Could not find a column labeled 'Well'"]
  else
    return ["Good!",(headers.to_set-[samp_h, plate_h, well_h].to_set).to_a]
  end
end


# This function is used to populate the database based on a flat file
# Input:
#     if_:      The input file path
#     debug:    Gives more verbose runtime information
#     web_mode:   Provides output designed to be parsed for the web layer to understand
#     store:    Uses the daybreaker key/value store to keep track of the progress
#     key:      The key to use when looking up the progress (the file name being processed)
#     opts:     Passed to CSV
# Output:
#   Will populate the Sample, Well, and Plate tables of the database based on the input file information
#     In web mode, it will store ['Good!', float(% complete)] in the daybreaker store[key], or ['Error', (error message)]
#     Otherwise a progress bar is shown indicating the progress in populating the database
#     Debug mode will be more verbose
def add_data(if_:nil, debug:false, web_mode:false, store:nil, key:nil, opts:{:headers => true, :col_sep => "\t", skip_blanks:true})
  require 'ruby-progressbar'
  require 'csv'

  # Web mode was requsted but no store/key were provided
  if web_mode and (store.nil? or key.nil?)
    return ["Error", "Must specify a store and key for web_mode"]
  end

  # No file was specified
  if if_.nil?
    store[key] = ["Error","No input file specified"] if web_mode
    puts "No input file specified" if not web_mode
    return
  end

  # Get the number of entries in the database flatfile
  num = File.read(if_).scan(/\n/).count
  puts "\nInserting data from #{if_}..." if not web_mode
  # Create progress bar
  pg = ProgressBar.create(:title      => "Progress",
                          :format     => '%a |%bᗧ%i|%p%%',
                          :length     => 100,
                          :progress_mark  => ' ',
                          :remainder_mark => '･',
                          :starting_at  => 0,
                          :total      => num) if not web_mode

  # Used to count entries
  entry_no = 0

  # Figure out headers
  begin
    entries = CSV.read(if_,opts)
  rescue
    store[key] = ["Error","Unable to read the header. Is this file tab-delimited?"] if web_mode
    puts "Unable to read the header. Is this file tab-delimited?" if not web_mode
    return
  end
  # Define column headers
  headers = entries[0].headers
  samp_h, plate_h, well_h, vol_h = [nil,nil,nil,nil]
  # Get matched column names (these should be verified first with check_db_file())
  headers.each { |head| head =~ /sample.*id/i? samp_h  = head : nil }
  headers.each { |head| head =~ /plate.*id/i?  plate_h = head : nil }
  headers.each { |head| head =~ /well/i?       well_h  = head : nil }
  headers.each { |head| head =~ /volume/i?     vol_h   = head : nil }


  # For each entry in the database flat file
  entries.each do |entry|
    #sleep(0.01)

    # Update the entry number and store the progress in the key store if in web mode
    entry_no += 1
    store[key] = ["Good!",entry_no/num.to_f] if web_mode

    # Get the plate and row,col of the well
    plate   = entry[plate_h]
    row,col = split_well(entry[well_h])
    # Get the remaining attributes
    attribs = entry.to_hash.clone
    attribs.delete(plate_h)
    attribs.delete(samp_h)
    attribs.delete(well_h)
    attribs.delete(vol_h)

    # Increment the progress bar
    pg.increment if not debug and not web_mode
    puts "\nEntry \##{entry_no}: [#{plate} #{row}#{col}] #{attribs}" if debug

    # Try to parse the line and add the entry to the database
    begin
      # Duplicates of plates are prevented by using an existing if encountered
      plate = Plate.first_or_create( :plateID    => entry[plate_h],
                                     :type       => "Source")

      # A before :save will prevent well duplications on a plate
      well = Well.new(:row         => row,
                      :col         => col,
                      :isOriginal  => true,
                      :plate       => plate,
                      :status      => "Used")

      # Sample attributes may not have been added to the Coding table yet.
      # Do so now if needed
      attribs.each do |a, v|
          previous = Coding.first(:attrib => a)
          if previous.nil?
              Coding.create!(:attrib  => a, :typeGuess => type_guess([v]))
          else
              Coding.first(:attrib => a).update!(:typeGuess => type_guess([v], previous: previous.typeGuess))
          end
      end
      # Decode the attributes and convert to json (better than doing it case-by-case as before)
      attribs.each{|k,v| attribs[k] = decode(k,v)}.to_json
      # Samples can only have one well, so the old relationship will be overwritten if a duplicate entry is encountered
      sample = Sample.new(:sampleID   => entry[samp_h],
                          :attribs    => attribs,
                          :wells      => [well],
                          :volume     => entry[vol_h])
      sample.save!
      well.sample = sample
      well.save!
      #plate.save!
    # Otherwise warn and continue
    rescue Exception => ex
      store[key] = ["Error", "An error occured when parsing line #{entry_no} of the input file."] if web_mode
      puts "An error occured when parsing line #{entry_no} of the input file." if not web_mode
      puts ex.message if not web_mode
      #puts ex.backtrace.join("\n") if not web_mode
      #next
      return
    end

  end
  pg.finish if not web_mode
  store[key] = ["Good!", 1.0] if web_mode # To indicate a 100% completion
end


# This function is used to check if the column headers of a batch file are correct to parse into the database
# Input:
#     if_:      The input file path
#     opts:     Passed to CSV
# Output:
#     Will return ['Good!', (non-required header names)] or ['Error', (error message)] depending on validity of the input file
def check_batch_file(if_:nil,  opts:{:headers => true, :col_sep => "\t"})
  require 'csv'

  if if_.nil?
    return ["Error","No file specified."]
  end

  # Figure out headers
  begin
    headers = CSV.read(if_,opts)[0].headers
  rescue
    return ["Error","Unable to read the header. Is this file tab-delimited?"]
  end

  required = ["BatchID","Source Plate","Source Well","Destination Plate","Destination Well","Volume"]
  if not required.to_set.subset? headers.to_set
    return ["Error","The headers of this file seem to be incorrect. Please check the file format."]
  else
    return ["Good!",""]
  end
end


# This function is used to populate the database based on a batch flat file information
# Input:
#     batch_files:      The input file paths of all batch files
#     debug:            Gives more verbose runtime information
#     web_mode:         Provides output designed to be parsed for the web layer to understand
#     store:            Uses the daybreaker key/value store to keep track of the progress
#     key:              The key to use when looking up the progress (the file name being processed)
#     opts:             Passed to CSV
# Output:
#   Will populate database with batch information (see check_batch file for the format)
#     In web mode, it will store ['Good!', float(% complete)] in the daybreaker store[key], or ['Error', (error message)]
#     Otherwise a progress bar is shown indicating the progress in populating the database
#     Debug mode will be more verbose
def load_batch_files(batch_files, debug:false, reset:false, web_mode:false, store:nil, key:nil, opts:{:headers => true, :col_sep => "\t", skip_blanks:true})
  require 'ruby-progressbar'
  require 'csv'

  # Web mode was requsted but no store/key were provided
  if web_mode and (store.nil? or key.nil?)
    return ["Error", "Must specify a store and key for web_mode"]
  end

  # No files were specified
  if batch_files.nil?
    store[key] = ["Error","No input files specified"] if web_mode
    puts "No input files specified" if not web_mode
    return
  end

  puts "\nAdding Batch files..." if not web_mode

  # Get total number of lines
  total_lines = 0
  for file in batch_files
    total_lines  += File.read(file).scan(/\n/).count
  end

  # For each batch file
  errors=[]
  entry_no = 0

  batch = nil
  dest_plates = []
  for file in batch_files
    # Get the batch name from the file name (ignoring leading path and file extensions)
    batch_file = file.split(/^(?:[\/a-z0-9_\-\. ]*\/)?([a-z0-9_\-\. ]+)(?:\.[\/a-z0-9_\-]*)?$/i)[1]
    puts "Processing \'#{batch_file}\'" if not web_mode

    # Create a progress bar for this batch
    pg = ProgressBar.create(:format         => '%t |%bᗧ%i|%p%%',
                            :length         => 100,
                            :progress_mark  => ' ',
                            :remainder_mark => '･',
                            :starting_at    => 0,
                            :total          => total_lines)  if not debug and not web_mode

    # For each entry in this batch file
    error_msg = "%{file}, line %{line}: %{message}"
    CSV.foreach("#{file}", opts) do |entry|
      batch_name = entry['BatchID']
      dest_plate = entry['Destination Plate']
      dest_well  = entry['Destination Well']
      src_plate  = entry['Source Plate']
      src_well   = entry['Source Well']
      dest_vol   = entry['Volume']

      # Update count and progress bar and user information
      entry_no += 1
      store[key] = ["Good!", entry_no/total_lines.to_f] if web_mode
      pg.title =  "Mapping #{src_plate} #{src_well} => #{dest_plate} #{dest_well}" if not debug and not web_mode
      pg.increment if not debug and not web_mode
      puts "Entry \##{entry_no}: Mapping #{src_plate} #{src_well} => #{dest_plate} #{dest_well}" if debug and not web_mode

      # Create the batch, skipping if it already exists
      if Batch.first(:batchID => batch_name).nil?
        begin
          batch = Batch.create(:batchID => batch_name)
          # Initialize pods for this batch
          (4..12).to_a.each { |n| batch.pods.create(:position => n) }
        rescue
          message = "The batch \'#{batch_name}\' could not be created."
          puts message if not web_mode
          errors << error_msg % {file: batch_name, line: $., message: message}
          next
        end
      else
        batch = Batch.first(:batchID => batch_name)
      end

      # Get the source plate and create or get the destination plate
      begin
        sp = Plate.first(:plateID => src_plate)
        dp = Plate.first(:plateID  => dest_plate,
                         :type     => "Destination")
        if dp.nil?
          dp = Plate.create(:plateID      => dest_plate,
                            :type         => "Destination",
                            :batchCreated => true)
        end
      rescue
        message = "The was an error creating or accessing database plates."
        puts message if not web_mode
        errors << error_msg % {file: batch_name, line: $., message: message}
        next
      end

      # Make sure the source plate exists or error out
      if sp.nil?
        message = "The source plate #{src_plate} does not exist in the database."
        puts message if not web_mode
        errors << error_msg % {file: batch_name, line: $., message: message}
        next
      end

      # Get the source and destination wells
      sw = lookup_well(src_plate, src_well)
      dw = lookup_well(dest_plate, dest_well)

      # Check that the source well exists
      if sw.nil?
        message = "The source well #{src_plate} #{src_well} does not exist.."
        puts message if not web_mode
        errors << error_msg % {file: batch_name, line: $., message: message}
        next
      end

      # Check for/get the next available pods for the two plates
      [dp, sp].each do |plate|
        if not batch.plates.include? plate
          pod = batch.pods.first(:type => plate.type, :plate => nil)
          if pod.nil?
            puts "\nWARNING: Out of #{plate.type} pods for #{plate.plateID} for batch #{batch.name}" if debug
            puts "Negotiating for a pod..." if debug
            next_available_pod = batch.pods.first(:plate => nil)
            if not next_available_pod.nil?
              puts "Found one at #{next_available_pod.type} (P#{next_available_pod.position})." if debug
              puts "Changing the pod type and using it." if debug
              next_available_pod.update!(:type => plate.type)
              pod = next_available_pod
            else
              message = "No more pods to place plate #{plate.plateID} for the robot."
              puts message if not web_mode
              errors << error_msg % {file: batch_name, line: $., message: message}
              next
            end
          end
          puts "Added #{plate.plateID} to #{batch.name} using pod at position #{pod.position}." if debug and not web_mode
          pod.plate_id = plate.id
          pod.save!
          batch.save!
        end
      end

      # Get the position of the destination well on the plate and create that object
      row, col = split_well(dest_well)
      begin
        # Get or create a new well for the destination
        dw = Well.first_or_create(:row => row, :col => col, :isOriginal => false, :plate => dp)
      rescue
        message = "Error creating the destination well #{dest_plate}: #{row}#{col}."
        puts message if not web_mode
        errors << error_msg % {file: batch_name, line: $., message: message}
        next
      end

      ## This code was used to have multiple potental mappings to each well
      ## This has been disabled to avoid sample mixing and to enforce the prefered method
      ##   of updating batch files to reflect updated mappings (also see Well attributes)
      # Update the source well as potentially providing the sample to the destination well
      #sw.destination_wells << dw
      # Update the destination well as potentially receiving a sample from the source well
      #dw.source_wells << sw

      # Make the first available mapping
      if sw.usable? and dw.provider.nil?
        if not sw.sample.volume.nil?
          if sw.sample.volume - (sw.sample.claimed_volume + dest_volume) < 0
            message = "Mapping conflict; Source #{src_plate} #{sw.short} does not have enough volume to provide this mapping. #{sw.sample.volume}; #{sw.sample.claimed_volume} claimed."
            puts message if not web_mode
            errors << error_msg % {file: batch_name, line: $., message: message}
            next
          end
        else
          # Volume isn't known, assume its good.
          batch.mappings.create(:volume => dest_vol, :provider => sw, :destination => dw)
        end
      else
        message = "Mapping conflict; #{src_plate}: #{sw.short} is \'#{sw.sample.status}\' and provides \'#{sw.destination(as_text:true)}\'; Destination is provided by #{dw.provider(as_text:true)}."
        puts message if not web_mode
        errors << error_msg % {file: batch_name, line: $., message: message}
        next
      end

      begin
        # Save both
        sw.save!
        dw.save!
        # Update the destination plates
        dest_plates << dp
        dest_plates.uniq!
      rescue
        message = "There was an issue saving well information for #{dest_plate} #{row}#{col}."
        puts message if not web_mode
        errors << error_msg % {file: batch_name, line: $., message: message}
        next
      end

        # Finsh the progress bar
      pg.finish if not debug and not web_mode
    end
  end
  store[key] = ["Good!", 1.0, errors] if web_mode # To indicate a 100% completion

  # Clear robot files if resetting
  %x(rm -rf db/robot_files/*) if reset
  # Clear gene titan files if resetting
  #%x(rm -rf db/gene_titan_files/*)
  return errors
end

def set_control_plates(plates)
  # Set control plate, and set all wells to control
  for plate_name in plates
    plate = Plate.first(:plateID => plate_name)
    plate.update(:type => "Control")
    plate.save!
    plate.wells.update({:isControl => true})
    plate.wells.save!
  end
end


def remove_all_batches(also_plates: true)
  Batch.all.destroy!
  Mapping.all.destroy!
  if also_plates
    Plate.all(:batchCreated => true).destroy!
  end
end

def mark_all_batches_complete(debug:false)
  puts "Marking batches as complete"
  total = Batch.count()
  pg = ProgressBar.create(:title          => sprintf("%27s", ""),
                          :format         => '%t |%bᗧ%i|%p%%',
                          :length         => 100,
                          :progress_mark  => ' ',
                          :remainder_mark => '･',
                          :starting_at    => 0,
                          :total          => total)
  pg.finish if debug

  Batch.all.each do |batch|
    pg.title =  "#{batch.name}"
    batch.complete!
    pg.increment
  end
end




def create_robot_file(batch_name, debug:false, default_vol:30)
  require 'csv'

  batch = Batch.first(:batchID => batch_name)
  return nil if batch.nil?
  robofile = File.join(File.dirname(__FILE__),"db","robot_files","#{batch.name}.csv")
  if File.exist?(robofile)
    FileUtils.rm_f(robofile)
    puts "#{batch.name}.csv deleted for recreation"
  end

  CSV.open(robofile, 'w') do |writer|
    batch.mappings.each do |map|
      sp = batch.pods.first(:plate_id => map.provider.plate.id)
      sw = map.provider.short
      dp = batch.pods.first(:plate_id => map.destination.plate.id)
      dw = map.destination.short
      samp = map.provider.sample
      vol = map.volume || default_vol
      if debug and not samp.nil?
        writer << ["P#{sp.position}",sw,"P#{dp.position}",dw,vol, samp.sampleID, sp.plate.plateID, dp.plate.plateID, samp.attribs]
      else
        writer << ["P#{sp.position}",sw,"P#{dp.position}",dw,vol]
      end
    end
  end
end

def make_all_robot_files(debug:true)
  require 'zip'
  directory = File.dirname(__FILE__),"db","robot_files"
  zipfile_name = File.join(File.dirname(__FILE__),"db","robot_files","robot_files.zip")
  if File.exist?(zipfile_name)
    FileUtils.rm_f(zipfile_name)
    puts "#{zipfile_name} deleted for recreation"
  end

  Batch.all.map(&:batchID).each do |batch|
    puts "Making batch file for #{batch}"
    create_robot_file(batch,debug:debug)
  end

  puts "Zipping to #{zipfile_name}"
  Zip::File.open(zipfile_name, Zip::File::CREATE) do |zipfile|
    Dir[File.join(directory, '**', '**')].each do |file|
      zipfile.add(file.sub(directory.join('/')+'/',''), file)
    end
  end
end


def create_gene_titan_file(plate_name)
  require 'ruby-progressbar'
  require 'spreadsheet'

  puts "\nMaking Gene Titan files..."
  plate = Plate.first(:plateID => plate_name)
  return nil if plate.nil?
  titanfile = File.join(File.dirname(__FILE__),"db","gene_titan_files","#{plate.name}.xls")
  if File.exist?(titanfile)
    FileUtils.rm_f(titanfile)
    puts "Gene Titan file #{plate.name}.xls deleted for recreation"
  end

  # Initialize the spreadsheet book and sheets
  Spreadsheet.client_encoding = 'UTF-8'
  book = Spreadsheet::Workbook.new
  sheet = book.create_worksheet :name => 'Samples'
  # Gene titan file requires 2 additional worksheets
  sheet2 = book.create_worksheet :name => 'DO_NOT_EDIT'
  sheet3 = book.create_worksheet :name => 'DO_NOT_EDIT_TEMPLATE_INFO'

  # For each sample in this plate
  idx = 0
  sheet.row(idx).push 'Sample File Path', 'Project', 'Plate Type', 'Probe Array Type', 'Probe Array Position', 'Barcode', 'Sample File Name', 'Array Name', 'VialID:Project:Text'
  plate.samples.each do |sample|
    idx = idx+1
    weird_sample_name = "#{plate.name}_#{sample.well.long}_#{plate.name}_#{sample.well.row}_#{sample.well.col}"
    sheet.row(idx).push '', plate.name, 'Axiom_ProArray-96', 'Axiom_ProArray', sample.well.long, '', weird_sample_name, weird_sample_name, sample.sampleID
  end

  # Add two "DO NOT EDIT" tabs
  format = Spreadsheet::Format.new :weight => :bold, :size => 12
  sheet2.row(0).push 'Project','Probe Array Type','Configuration'
  sheet2.row(0).set_format(0, format)
  sheet2.row(0).set_format(1, format)
  sheet2.row(0).set_format(2, format)
  sheet2.row(1).push 'Default','','Format: GeneTitan Array Plate Registration'
  sheet2.row(2).push '','','Version: 2.0.0'
  # The other "DO NOT EDIT" tab
  sheet3.row(0).push 'Attribute Name','Attribute Type','Attribute Required'
  sheet3.row(0).set_format(0, format)
  sheet3.row(0).set_format(1, format)
  sheet3.row(0).set_format(2, format)
  sheet3.row(1).push 'VialID:Project','Text','False'
  book.write titanfile
end


def load_qc_files(qc_files:["#{Dir.pwd}/db/qualities.xlsx"], verbose:false)
  require 'roo'
  for file in qc_files
    book = Roo::Spreadsheet.open(file)
    for sheet_name in book.sheets
      begin
        Plate.first(:plateID => sheet_name).isComplete
      rescue
        puts "'#{sheet_name}' doesn't look like a plate in the database, skipping this sheet..."
        next
      end
      sheet = book.sheet(sheet_name)
      if not Plate.first(:plateID => sheet_name).isComplete
        puts "'#{sheet_name}' has not been marked as complete, so no samples are available to attach quality scores to..."
        next
      end

      puts "Reading '#{sheet_name}'..."
      1.upto(sheet.last_row) do |line|

        # Look for a hint on whats coming up based on cell A of this line
        block_hint = sheet.cell(line, 'A')
        case block_hint
        when /Missing wells for ([\d\w]+):/

          loop do
            line = line+1
            lead = sheet.cell(line, 'A')
            break if lead != nil
            row, col = sheet.cell(line, 'B').split(".")[0].split("_")[-2..-1]
            # Insert
            puts "Missing! #{sheet_name} #{row},#{col}"
          end
        when /Failed DashQC >= ([\d.]+):/
          qc_cutoff = block_hint.match(/Failed DashQC >= ([\d.]+):/)[1].to_f
          loop do
            line = line+1
            lead = sheet.cell(line, 'A')
            break if lead != nil
            row, col = sheet.cell(line, 'B').split(".")[0].split("_")[-2..-1]
            value = sheet.cell(line, 'C')
            # Insert
            puts "Bad QC   #{sheet_name} #{row},#{col}:  #{value}" if verbose

            sample = Plate.first(:plateID => sheet_name).wells(:row => row, :col => col).first.sample
            sample.update!(:failedQC => true, :quality => value)
          end
        when /Failed call rate >= ([\d.]+):/
          call_cuttoff = block_hint.match(/Failed call rate >= ([\d.]+):/)[1].to_f
          loop do
            line = line+1
            lead = sheet.cell(line, 'A')
            break if lead != nil
            row, col = sheet.cell(line, 'B').split(".")[0].split("_")[-2..-1]
            value = sheet.cell(line, 'C')
            # Insert
            puts "Bad call #{sheet_name} #{row},#{col}:  #{value}" if verbose

            sample = Plate.first(:plateID => sheet_name).wells(:row => row, :col => col).first.sample
            sample.update!(:failedCall => true, :callRate => value)
          end
        when /Plate [\d\w]+ QC summary:/
          line = line+2
          loop do
            line = line+1
            lead = sheet.cell(line, 'A')
            next if sheet.cell(line,'C') == "NA"
            break if lead == nil or line > sheet.last_row
            row, col = split_well(sheet.cell(line, 'A').split("_")[1])
            qc_value = sheet.cell(line, 'B')
            call_value = sheet.cell(line,'C')
            # Insert
            puts "Good!    #{sheet_name} #{row},#{col}:  #{qc_value}    #{call_value}" if verbose

            sample = Plate.first(:plateID => sheet_name).wells(:row => row, :col => col).first.sample
            sample.update!(:quality => qc_value, :callRate => call_value)
          end
        end
      end
    end
  end
end


DataMapper.auto_upgrade!
