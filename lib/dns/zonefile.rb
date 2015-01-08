require 'dns/zonefile/parser'

module DNS
  module Zonefile
    class << self
      def parse(zone_string)
	parser = DNS::Zonefile::Parser.new
	if result = parser.parse(zone_string)
	  result
	else
	  raise ParsingError, parser.failure_reason
	end
      end

      def load(zone_string, alternate_origin=nil)
	Zone.new(parse(zone_string).entries, alternate_origin)
      end
    end

    class ParsingError < RuntimeError ; end
    class UnknownRecordType < RuntimeError ; end
    class Zone
      attr_reader :origin, :soa
      attr_reader :records

      def initialize(entries, alternate_origin=nil)
	alternate_origin ||= '.'
	@records = []
	@vars = {'origin'=>alternate_origin, :last_host=>'.'}
	entries.each do |e|
	  case e.parse_type
	  when :variable
	    #STDERR.puts "Handling variable: #{e.name.text_value.downcase} = #{e.value.text_value}"
	    case key = e.name.text_value.downcase
	    when 'ttl'
	      @vars[key] = e.value.text_value.to_i
	    else
	      @vars[key] = e.value.text_value
	    end
	  when :soa
	    @records << SOA.new(@vars, e)
	  when :record
	    case e.record_type
	    when 'A'      then @records << A.new(@vars, e)
	    when 'AAAA'   then @records << AAAA.new(@vars, e)
	    when 'CNAME'  then @records << CNAME.new(@vars, e)
	    when 'MX'     then @records << MX.new(@vars, e)
	    when 'NAPTR'  then @records << NAPTR.new(@vars, e)
	    when 'NS'     then @records << NS.new(@vars, e)
	    when 'PTR'    then @records << PTR.new(@vars, e)
	    when 'SRV'    then @records << SRV.new(@vars, e)
	    when 'SPF'    then @records << SPF.new(@vars, e)
	    when 'TXT'    then @records << TXT.new(@vars, e)
	    when 'SOA'    then ;
	    when 'X-MAIL-FWD' then @records << X_MAIL_FWD.new(@vars, e)
	    when 'X-WEB-FWD'  then @records << X_WEB_FWD.new(@vars, e)
	    else
	      raise UnknownRecordType, "Unknown record type: #{e.record_type}; #{e.text_value}"
	    end
	  end
	end
      end

      def soa
	records_of(SOA).first
      end

      def records_of(kl)
	@records.select{|r| r.instance_of? kl}
      end
    end

    class Record
      # assign, with handling for '@'
      def self.writer_for_at(*attribs)
	attribs.each do |attrib|
	  class_eval <<-MTH, __FILE__, __LINE__+1
	    def #{attrib}=(val)
	      @#{attrib} = val.gsub('@', vars['origin'])
	    end
	  MTH
	end
      end

      # assign, with handling for '@', with inheritance
      def self.inheriting_writer_for_at(*attribs)
	attribs.each do |attrib|
	  class_eval <<-MTH, __FILE__, __LINE__+1
	    def #{attrib}=(val)
	      if val.strip.empty?
		@#{attrib} = vars[:last_host]
	      else
		@#{attrib} = val.gsub('@', vars['origin'])
	      end
	    end
	  MTH
	end
      end

      # assign, with handling for global TTL
      def self.writer_for_ttl(*attribs)
	attribs.each do |attrib|
	  class_eval <<-MTH, __FILE__, __LINE__+1
	    def #{attrib}=(val)
	      @#{attrib} = val || vars['ttl']
	    end
	  MTH
	end
      end

      attr_reader :ttl
      attr_writer :klass
      writer_for_ttl :ttl

      attr_reader :vars

      def initialize(vars, parsed=nil)
	@vars = vars

	if parsed
	  if respond_to?(:host=) && parsed.respond_to?(:host)
	    self.host = parsed.host.to_s
	    vars[:last_host] = host
	  end

	  self.ttl = (parsed.ttl || vars['ttl']).to_i
	  self.klass = parsed.klass.to_s
	end
      end

      def klass
	@klass = nil if @klass == ''
	@klass ||= 'IN'
      end

    end

    class SOA < Record
      attr_accessor :origin, :nameserver, :responsible_party, :serial, :refresh_time, :retry_time, :expiry_time, :nxttl

      writer_for_at  :origin, :nameserver, :responsible_party

      def initialize(vars, zonefile_soa=nil)
	super

	@vars = vars
	if zonefile_soa
	  self.origin            = zonefile_soa.origin.to_s
	  vars[:last_host]       = self.origin
	  self.nameserver        = zonefile_soa.ns.to_s
	  self.responsible_party = zonefile_soa.rp.to_s
	  self.serial            = zonefile_soa.serial.to_i
	  self.refresh_time      = zonefile_soa.refresh.to_i
	  self.retry_time        = zonefile_soa.reretry.to_i
	  self.expiry_time       = zonefile_soa.expiry.to_i
	  self.nxttl             = zonefile_soa.nxttl.to_i
	end
      end
    end

    class A < Record
      attr_accessor :host, :address

      inheriting_writer_for_at  :host

      def initialize(vars, zonefile_record)
	super

	@vars = vars
	if zonefile_record
	  self.address      = zonefile_record.ip_address.to_s
	end
      end
    end

    class AAAA < A
    end

    class CNAME < Record
      attr_accessor :host, :domainname

      inheriting_writer_for_at  :host
      writer_for_at :domainname

      def initialize(vars, zonefile_record)
	super

	@vars = vars
	if zonefile_record
	  self.domainname   = zonefile_record.target.to_s
	end
      end

      alias :target :domainname
      alias :alias :host
    end

    class MX < Record
      attr_accessor :host, :priority, :domainname

      inheriting_writer_for_at  :host
      writer_for_at :domainname

      def initialize(vars, zonefile_record)
	super

	@vars = vars
	if zonefile_record
	  self.priority     = zonefile_record.priority.to_i
	  self.domainname   = zonefile_record.exchanger.to_s
	end
      end

      alias :exchange :domainname
      alias :exchanger :domainname
    end

    class NAPTR < Record
      attr_accessor :host, :data

      inheriting_writer_for_at  :host

      def initialize(vars, zonefile_record)
	super

	@vars = vars
	if zonefile_record
	  self.data         = zonefile_record.data.to_s
	end
      end
    end

    class NS < Record
      attr_accessor :host, :domainname

      inheriting_writer_for_at  :host
      writer_for_at :domainname

      def initialize(vars, zonefile_record)
	super

	@vars = vars
	if zonefile_record
	  self.domainname   = zonefile_record.nameserver.to_s
	end
      end

      alias :nameserver :domainname
    end

    class PTR < Record
      attr_accessor :host, :domainname

      inheriting_writer_for_at  :host
      writer_for_at :domainname

      def initialize(vars, zonefile_record)
	super

	@vars = vars
	if zonefile_record
	  self.domainname   = zonefile_record.target.to_s
	end
      end

      alias :target :domainname
    end

    class SRV < Record
      attr_accessor :host, :priority, :weight, :port, :domainname

      inheriting_writer_for_at  :host
      writer_for_at :domainname

      def initialize(vars, zonefile_record)
	super

	@vars = vars
	if zonefile_record
	  self.priority     = zonefile_record.priority.to_i
	  self.weight       = zonefile_record.weight.to_i
	  self.port         = zonefile_record.port.to_i
	  self.domainname   = zonefile_record.target.to_s
	end
      end

      alias :target :domainname
    end

    class TXT < Record
      attr_accessor :host, :data

      inheriting_writer_for_at  :host

      def initialize(vars, zonefile_record)
	super

	@vars = vars
	if zonefile_record
	  self.data         = zonefile_record.data.to_s
	end
      end
    end

    class SPF < TXT
    end

    class X_MAIL_FWD < Record
      attr_accessor :recipient, :targets

      def initialize(vars, zonefile_record)
	if zonefile_record
	  self.recipient = zonefile_record.recipient.to_s
	  self.targets = zonefile_record.targets.to_s
	end

	# needs #recipient
	super
      end

      def host
	recipient.split('@', 2).last
      end

      def host=(s)
	r_local = recipient.split('@', 2).first
	self.recipient = "#{r_local}@#{s}"
      end
    end

    class X_WEB_FWD < Record
      attr_accessor :host, :type, :target

      inheriting_writer_for_at :host

      def initialize(vars, zonefile_record)
	super
	@vars = vars

	if zonefile_record
	  self.type = zonefile_record.fwtype.to_s
	  self.target = zonefile_record.target.to_s
	end
      end
    end

  end
end

# vim: ts=8 sw=2 noexpandtab
