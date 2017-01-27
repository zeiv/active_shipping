# -*- encoding: utf-8 -*-

module ActiveShipping
  # After getting an API login from USPS (looks like '123YOURNAME456'),
  # run the following test:
  #
  # usps = USPS.new(:login => '123YOURNAME456', :test => true)
  # usps.valid_credentials?
  #
  # This will send a test request to the USPS test servers, which they ask you
  # to do before they put your API key in production mode.
  class USPS < Carrier
    EventDetails = Struct.new(:description, :time, :zoneless_time, :location, :event_code)
    ONLY_PREFIX_EVENTS = ['DELIVERED','OUT FOR DELIVERY']
    self.retry_safe = true

    cattr_reader :name
    @@name = "USPS"

    WORLD_SHIPMENT_API_REVISION = '2'
    RATES_DOMAIN = 'production.shippingapis.com'
    TEST_RATES_DOMAIN = 'stg-production.shippingapis.com'
    LABELS_DOMAIN = 'secure.shippingapis.com'
    RESOURCE = 'ShippingAPI.dll'

    DOMAINS = {
      :us_rates => { live: RATES_DOMAIN, test: TEST_RATES_DOMAIN },
      :world_rates => { live: RATES_DOMAIN, test: TEST_RATES_DOMAIN },
      :us_shipment => { live: LABELS_DOMAIN, test: LABELS_DOMAIN },
      :us_shipment_test => { live: LABELS_DOMAIN, test: LABELS_DOMAIN },
      :world_shipment => { live: LABELS_DOMAIN, test: LABELS_DOMAIN },
      :world_shipment_test => { live: LABELS_DOMAIN, test: LABELS_DOMAIN },
      :test => { live: LABELS_DOMAIN, test: LABELS_DOMAIN },
      :track => { live: RATES_DOMAIN, test: TEST_RATES_DOMAIN }
    }

    API_CODES = {
      :us_rates => 'RateV4',
      :world_rates => 'IntlRateV2',
      :us_shipment => 'DeliveryConfirmationV4',
      :us_shipment_test => 'DelivConfirmCertifyV4',
      :world_shipment => 'ExpressMailIntl',
      :world_shipment_test => 'ExpressMailIntlCertify',
      :test => 'CarrierPickupAvailability',
      :track => 'TrackV2'
    }

    XML_ROOTS = {
      :us_shipment => 'DeliveryConfirmationV4.0Request',
      :us_shipment_test => 'DelivConfirmCertifyV4.0Request',
      :world_shipment => 'ExpressMailIntlRequest',
      :world_shipment_test => 'ExpressMailIntlCertifyRequest'
    }

    USE_SSL = {
      :us_rates => false,
      :world_rates => false,
      :us_shipment =>  true,
      :us_shipment_test => true,
      :world_shipment => true,
      :world_shipment_test => true,
      :test => true,
      :track => false
    }

    CONTAINERS = {
      rectangular: 'RECTANGULAR',
      variable: 'VARIABLE',
      box: 'FLAT RATE BOX',
      box_large: 'LG FLAT RATE BOX',
      box_medium: 'MD FLAT RATE BOX',
      box_small: 'SM FLAT RATE BOX',
      envelope: 'FLAT RATE ENVELOPE',
      envelope_legal: 'LEGAL FLAT RATE ENVELOPE',
      envelope_padded: 'PADDED FLAT RATE ENVELOPE',
      envelope_gift_card: 'GIFT CARD FLAT RATE ENVELOPE',
      envelope_window: 'WINDOW FLAT RATE ENVELOPE',
      envelope_small: 'SM FLAT RATE ENVELOPE',
      package_service: 'PACKAGE SERVICE'
    }

    MAIL_TYPES = {
      :package => 'Package',
      :postcard => 'Postcards or aerogrammes',
      :matter_for_the_blind => 'Matter for the blind',
      :envelope => 'Envelope'
    }

    LABEL_TYPES = {
      :pdf => 'PDF',
      :tif => 'TIF'
    }
    LABEL_TYPE = LABEL_TYPES[:pdf]

    US_SERVICES = {
      :first_class => 'FIRST CLASS',
      :priority => 'PRIORITY',
      :express => 'EXPRESS',
      :bpm => 'BPM',
      :parcel => 'PARCEL',
      :media => 'MEDIA',
      :library => 'LIBRARY',
      :online => 'ONLINE',
      :plus => 'PLUS',
      :all => 'ALL'
    }

    SHIPMENT_SERVICES = {
      :first_class => 'FIRST CLASS',
      :priority => 'PRIORITY',
      :media => 'MEDIA MAIL',
      :library => 'LIBRARY MAIL'
    }

    DEFAULT_SERVICE = Hash.new(:all).update(
      :base => :online,
      :plus => :plus
    )

    DOMESTIC_RATE_FIELD = Hash.new('Rate').update(
      :base => 'CommercialRate',
      :plus => 'CommercialPlusRate'
    )

    INTERNATIONAL_RATE_FIELD = Hash.new('Postage').update(
      :base => 'CommercialPostage',
      :plus => 'CommercialPlusPostage'
    )

    COMMERCIAL_FLAG_NAME = {
      :base => 'CommercialFlag',
      :plus => 'CommercialPlusFlag'
    }

    FIRST_CLASS_MAIL_TYPES = {
      :letter => 'LETTER',
      :flat => 'FLAT',
      :parcel => 'PARCEL',
      :post_card => 'POSTCARD',
      :package_service => 'PACKAGESERVICE'
    }

    CONTENT_TYPES = Hash.new('MERCHANDISE').update(
      :sample => 'SAMPLE',
      :gift => 'GIFT',
      :documents => 'DOCUMENTS',
      :return => 'RETURN',
      :humanitarian => 'HUMANITARIAN',
      :dangerous_goods => 'DANGEROUSGOODS',
      :cremated_remains => 'CrematedRemains',
      :nonnegotiable_document => 'NonnegotiableDocument'
    )

    ATTEMPTED_DELIVERY_CODES = %w(02 53 54 55 56 H0)

    # Array of U.S. possessions according to USPS: https://www.usps.com/ship/official-abbreviations.htm

    # TODO: figure out how USPS likes to say "Ivory Coast"
    #
    # Country names:
    # http://pe.usps.gov/text/Imm/immctry.htm
    COUNTRY_NAME_CONVERSIONS = {
      "BA" => "Bosnia-Herzegovina",
      "CD" => "Congo, Democratic Republic of the",
      "CG" => "Congo (Brazzaville),Republic of the",
      "CI" => "Côte d'Ivoire (Ivory Coast)",
      "CK" => "Cook Islands (New Zealand)",
      "FK" => "Falkland Islands",
      "GB" => "Great Britain and Northern Ireland",
      "GE" => "Georgia, Republic of",
      "IR" => "Iran",
      "KN" => "Saint Kitts (St. Christopher and Nevis)",
      "KP" => "North Korea (Korea, Democratic People's Republic of)",
      "KR" => "South Korea (Korea, Republic of)",
      "LA" => "Laos",
      "LY" => "Libya",
      "MC" => "Monaco (France)",
      "MD" => "Moldova",
      "MK" => "Macedonia, Republic of",
      "MM" => "Burma",
      "PN" => "Pitcairn Island",
      "RU" => "Russia",
      "SK" => "Slovak Republic",
      "TK" => "Tokelau (Union) Group (Western Samoa)",
      "TW" => "Taiwan",
      "TZ" => "Tanzania",
      "VA" => "Vatican City",
      "VG" => "British Virgin Islands",
      "VN" => "Vietnam",
      "WF" => "Wallis and Futuna Islands",
      "WS" => "Western Samoa"
    }

    TRACKING_ODD_COUNTRY_NAMES = {
      'TAIWAN' => 'TW',
      'MACEDONIA THE FORMER YUGOSLAV REPUBLIC OF'=> 'MK',
      'MICRONESIA FEDERATED STATES OF' => 'FM',
      'MOLDOVA REPUBLIC OF' => 'MD',
    }

    ESCAPING_AND_SYMBOLS = /&lt;\S*&gt;/
    LEADING_USPS = /^USPS /
    TRAILING_ASTERISKS = /\*+$/
    SERVICE_NAME_SUBSTITUTIONS = /#{ESCAPING_AND_SYMBOLS}|#{LEADING_USPS}|#{TRAILING_ASTERISKS}/

    def find_tracking_info(tracking_number, options = {})
      options = @options.merge(options)
      tracking_request = build_tracking_request(tracking_number, options)
      response = commit(:track, tracking_request, options[:test] || false)
      parse_tracking_response(response).first
    end

    def batch_find_tracking_info(tracking_infos, options = {})
      options = @options.update(options)
      tracking_request = build_tracking_batch_request(tracking_infos, options)
      response = commit(:track, tracking_request, options[:test] || false)
      parse_tracking_response(response, fault_tolerant: true)
    end

    def self.size_code_for(package)
      if package.inches(:max) <= 12
        'REGULAR'
      else
        'LARGE'
      end
    end

    # from info at http://www.usps.com/businessmail101/mailcharacteristics/parcels.htm
    #
    # package.options[:books] -- 25 lb. limit instead of 35 for books or other printed matter.
    #                             Defaults to false.
    def self.package_machinable?(package, options = {})
      at_least_minimum =  package.inches(:length) >= 6.0 &&
                          package.inches(:width) >= 3.0 &&
                          package.inches(:height) >= 0.25 &&
                          package.ounces >= 6.0
      at_most_maximum  =  package.inches(:length) <= 34.0 &&
                          package.inches(:width) <= 17.0 &&
                          package.inches(:height) <= 17.0 &&
                          package.pounds <= (package.options[:books] ? 25.0 : 35.0)
      at_least_minimum && at_most_maximum
    end

    def requirements
      [:login]
    end

    def find_rates(origin, destination, packages, options = {})
      validate_in_us(origin, 'origin has to be a US address')

      options = @options.merge(options)

      origin = Location.from(origin)
      destination = Location.from(destination)
      packages = Array(packages)

      if destination.domestic?
        us_rates(origin, destination, packages, options)
      else
        world_rates(origin, destination, packages, options)
      end
    end

    def valid_credentials?
      # Cannot test with find_rates because USPS doesn't allow that in test mode
      test_mode? ? canned_address_verification_works? : super
    end

    def maximum_weight
      Mass.new(70, :pounds)
    end

    def extract_event_details(node)
      description = node.at('Event').text.upcase

      if prefix = ONLY_PREFIX_EVENTS.find { |p| description.start_with?(p) }
        description = prefix
      end

      time = if node.at('EventDate').text.present?
        timestamp = "#{node.at('EventDate').text}, #{node.at('EventTime').text}"
        Time.parse(timestamp)
      else
        # Epoch time, because we need to sort properly by time
        Time.at(0)
      end

      event_code = node.at('EventCode').text
      city = node.at('EventCity').try(:text)
      state = node.at('EventState').try(:text)
      zip_code = node.at('EventZIPCode').try(:text)

      country_node = node.at('EventCountry')
      country = country_node ? country_node.text : ''
      country = 'UNITED STATES' if country.empty?
      # USPS returns upcased country names which ActiveUtils doesn't recognize without translation
      country = find_country_code_case_insensitive(country)

      zoneless_time = Time.utc(time.year, time.month, time.mday, time.hour, time.min, time.sec)
      location = Location.new(city: city, state: state, postal_code: zip_code, country: country)
      EventDetails.new(description, time, zoneless_time, location, event_code)
    end

    def maximum_address_field_length
      # https://www.usps.com/business/web-tools-apis/address-information-api.pdf
      38
    end

    def create_shipment(origin, destination, packages, options = {})
      validate_in_us(origin, 'origin has to be a US address')

      options = @options.merge(options)
      packages = Array(packages)

      raise ArgumentError, "Multiple packages are not supported yet." if packages.length > 1

      origin = Location.from(origin)
      destination = Location.from(destination)

      action = shipment_action(origin, destination, options[:test])

      request = build_shipment_request(action, origin, destination, packages[0], options)
      response = commit(action, request, options[:test])

      parse_shipment_response(response, options)
    end

    protected

    def validate_in_us(location, message = 'location not in US')
      unless location.domestic?
        raise ArgumentError, message
      end
    end

    def shipment_action(origin, destination, test = false)
      if destination.domestic?
        test ? :us_shipment_test : :us_shipment
      else
        test ? :world_shipment_test : :world_shipment
      end
    end

    def build_tracking_request(tracking_number, options = {})
      build_tracking_batch_request([{
        number: tracking_number,
        destination_zip: options[:destination_zip],
        mailing_date: options[:mailing_date]
      }], options)
    end

    def build_tracking_batch_request(tracking_infos, options)
      xml_builder = Nokogiri::XML::Builder.new do |xml|
        xml.TrackFieldRequest('USERID' => options[:login]) do
          xml.Revision { xml.text('1') }
          xml.ClientIp { xml.text(options[:client_ip] || '127.0.0.1') }
          xml.SourceId { xml.text(options[:source_id] || 'active_shipping') }
          tracking_infos.each do |info|
            xml.TrackID('ID' => info[:number]) do
              xml.DestinationZipCode { xml.text(strip_zip(info[:destination_zip]))} if info[:destination_zip]
              if info[:mailing_date]
                formatted_date = info[:mailing_date].strftime('%Y-%m-%d')
                xml.MailingDate { xml.text(formatted_date)}
              end
            end
          end
        end
      end
      xml_builder.to_xml
    end

    def us_rates(origin, destination, packages, options = {})
      request = build_us_rate_request(packages, origin.zip, destination.zip, options)
      # never use test mode; rate requests just won't work on test servers
      parse_rate_response(origin, destination, packages, commit(:us_rates, request, false), options)
    end

    def world_rates(origin, destination, packages, options = {})
      request = build_world_rate_request(origin, packages, destination, options)
      # never use test mode; rate requests just won't work on test servers
      parse_rate_response(origin, destination, packages, commit(:world_rates, request, false), options)
    end

    # Once the address verification API is implemented, remove this and have valid_credentials? build the request using that instead.
    def canned_address_verification_works?
      return false unless @options[:login]
      request = <<-EOF
      <?xml version="1.0" encoding="UTF-8"?>
      <CarrierPickupAvailabilityRequest USERID="#{URI.encode(@options[:login])}">
        <FirmName>Shopifolk</FirmName>
        <SuiteOrApt>Suite 0</SuiteOrApt>
        <Address2>18 Fair Ave</Address2>
        <Urbanization />
        <City>San Francisco</City>
        <State>CA</State>
        <ZIP5>94110</ZIP5>
        <ZIP4>9411</ZIP4>
      </CarrierPickupAvailabilityRequest>
      EOF
      xml = Nokogiri.XML(commit(:test, request, true)) { |config| config.strict }
      xml.at('/CarrierPickupAvailabilityResponse/City').try(:text) == 'SAN FRANCISCO' && xml.at('/CarrierPickupAvailabilityResponse/Address2').try(:text) == '18 FAIR AVE'
    end

    def build_shipment_request(action, origin, destination, package, options = {})
      if destination.domestic?
        build_us_shipment_request(action, origin, destination, package, options)
      else
        build_world_shipment_request(action, origin, destination, package, options)
      end
    end

    def build_us_shipment_request(action, origin, destination, package, options = {})
      xml_builder = Nokogiri::XML::Builder.new do |xml|
        xml.send(XML_ROOTS[action].to_sym, 'USERID' => @options[:login]) do
          service = SHIPMENT_SERVICES[options[:service]]

          unless service
            raise ArgumentError, "Service is not provided or not supported."
          end

          build_us_location_node(xml, 'From', origin)
          build_us_location_node(xml, 'To', destination)

          xml.WeightInOunces("%0.1f" % [package.ounces, 1].max)
          xml.ServiceType(service)

          xml.ImageType(LABEL_TYPE)

          size_code = USPS.size_code_for(package)
          container = CONTAINERS[package.options[:container]]
          container ||= (package.cylinder? ? 'NONRECTANGULAR' : 'RECTANGULAR') if size_code == 'LARGE'
          xml.Container(container)

          xml.Size(size_code)
        end
      end

      save_request(xml_builder.to_xml)
    end

    def build_us_location_node(xml, prefix, address)
      array = [
        ['Name', address.name],
        ['Firm', address.company],
        ['Address1', address.address1],
        ['Address2', address.address2 || address.address1],
        ['City', address.city],
        ['State', address.state],
        ['Zip5', strip_zip(address.zip)]
      ]
      array << ['Zip4', strip_zip4(address.zip)] if strip_zip4(address.zip)

      array.each do |key, value|
        xml.public_send(prefix + key, value)
      end
    end

    def build_world_shipment_request(action, origin, destination, package, options = {})
      xml_builder = Nokogiri::XML::Builder.new do |xml|
        xml.send(XML_ROOTS[action].to_sym, 'USERID' => @options[:login]) do
          xml.Revision(WORLD_SHIPMENT_API_REVISION)
          service = SHIPMENT_SERVICES[options[:service]]

          unless service
            raise ArgumentError, "Service is not provided or not supported."
          end

          build_world_location_node(xml, 'From', origin)
          build_world_location_node(xml, 'To', destination)

          size_code = USPS.size_code_for(package)
          container = CONTAINERS[package.options[:container]]
          container ||= (package.cylinder? ? 'NONRECTANGULAR' : 'RECTANGULAR') if size_code == 'LARGE'
          xml.Container(container)

          xml.ShippingContents do |xml|
            xml.ItemDetail do |xml|
              xml.Description("Item delivery")
              xml.Quantity(1)
              xml.Value(package.value)
              xml.NetPounds(package.pounds.to_i)
              xml.NetOunces("%0.1f" % [package.ounces, 1].max)
              xml.HSTariffNumber(0)
              xml.CountryOfOrigin('United States')
            end
          end

          xml.GrossPounds([package.pounds.to_i, 1].max)
          xml.GrossOunces(package.ounces.to_i)
          xml.ContentType(CONTENT_TYPES[package.options[:content_type]])
          xml.Agreement('Y')
          xml.ImageType(LABEL_TYPE)

          xml.Size(size_code)

          xml.Length(package.dimensions[0].to_f)
          xml.Width(package.dimensions[1].to_f)
          xml.Height(package.dimensions[2].to_f)
        end
      end

      save_request(xml_builder.to_xml)
    end

    def build_world_location_node(xml, prefix, address)
      array = [
        ['FirstName', address.first_name],
        ['LastName', address.last_name],
        ['Firm', address.company],
        ['Address1', address.address1],
        ['Address2', address.address2 || address.address1],
        ['City', address.city],
      ]

      unless address.domestic?
        array << ['Country', address.country]
        array << ['PostalCode', address.zip]
        array << ['POBoxFlag', address.po_box? ? 'Y' : 'N']
      end

      if address.domestic?
        array << ['State', address.state]
        array << ['Zip5', strip_zip(address.zip)]
        array << ['Zip4', strip_zip4(address.zip)] if strip_zip4(address.zip)
      end

      array << ['Phone', strip_phone(address.phone)]

      array.each do |key, value|
        xml.public_send(prefix + key, value)
      end
    end

    def parse_shipment_response(response, options = {})
      success = true
      message = ''
      labels = []

      xml = Nokogiri.XML(response)

      if error = xml.at_xpath('/Error | //ServiceErrors/ServiceError')
        success = false
        message = error.at('Description').text
      end

      unless error
        international_response = xml.at_css('ExpressMailIntlResponse').present? ||
          xml.at_css('ExpressMailIntlCertifyResponse').present?

        if international_response
          xml.search("*").select do |element|
            # select all elements with "Image" in their name
            element.name =~ /Image/ && element.content.present? 
          end.each do |element|
            labels << Label.new(xml.at_css('BarcodeNumber').content,
                                Base64.decode64(element.content))
          end
        else
          labels << Label.new(xml.at_css('DeliveryConfirmationNumber').content,
                              Base64.decode64(xml.at_css('DeliveryConfirmationLabel').content))
        end
      end

      LabelResponse.new(success, message, Hash.from_xml(response),
                        :xml => response, :request => last_request,
                        :labels => labels, :test => options[:test])
    end

    # options[:service] --    One of [:first_class, :priority, :express, :bpm, :parcel,
    #                          :media, :library, :online, :plus, :all]. defaults to :all.
    # options[:books] --      Either true or false. Packages of books or other printed matter
    #                          have a lower weight limit to be considered machinable.
    # package.options[:container] --  Can be :rectangular, :variable, or a flat rate container
    #                                 defined in CONTAINERS.
    # package.options[:machinable] -- Either true or false. Overrides the detection of
    #                                  "machinability" entirely.
    def build_us_rate_request(packages, origin_zip, destination_zip, options = {})
      xml_builder = Nokogiri::XML::Builder.new do |xml|
        xml.RateV4Request('USERID' => @options[:login]) do
          Array(packages).each_with_index do |package, id|
            xml.Package('ID' => id) do
              commercial_type = commercial_type(options)
              default_service = DEFAULT_SERVICE[commercial_type]
              service         = options.fetch(:service, default_service).to_sym

              if commercial_type && service != default_service
                raise ArgumentError, "Commercial #{commercial_type} rates are only provided with the #{default_service.inspect} service."
              end

              xml.Service(US_SERVICES[service])
              xml.FirstClassMailType(FIRST_CLASS_MAIL_TYPES[options[:first_class_mail_type].try(:to_sym)])
              xml.ZipOrigination(strip_zip(origin_zip))
              xml.ZipDestination(strip_zip(destination_zip))
              xml.Pounds(0)
              xml.Ounces("%0.1f" % [package.ounces, 1].max)
              size_code = USPS.size_code_for(package)
              container = CONTAINERS[package.options[:container]]
              container ||= (package.cylinder? ? 'NONRECTANGULAR' : 'RECTANGULAR') if size_code == 'LARGE'
              xml.Container(container)
              xml.Size(size_code)
              xml.Width("%0.2f" % package.inches(:width))
              xml.Length("%0.2f" % package.inches(:length))
              xml.Height("%0.2f" % package.inches(:height))
              xml.Girth("%0.2f" % package.inches(:girth))
              is_machinable = if package.options.has_key?(:machinable)
                package.options[:machinable] ? true : false
              else
                USPS.package_machinable?(package)
              end
              xml.Machinable(is_machinable.to_s.upcase)
            end
          end
        end
      end
      save_request(xml_builder.to_xml)
    end

    # important difference with international rate requests:
    # * services are not given in the request
    # * package sizes are not given in the request
    # * services are returned in the response along with restrictions of size
    # * the size restrictions are returned AS AN ENGLISH SENTENCE (!?)
    #
    #
    # package.options[:mail_type] -- one of [:package, :postcard, :matter_for_the_blind, :envelope].
    #                                 Defaults to :package.
    def build_world_rate_request(origin, packages, destination, options)
      country = COUNTRY_NAME_CONVERSIONS[destination.country.code(:alpha2).value] || destination.country.name
      xml_builder = Nokogiri::XML::Builder.new do |xml|
        xml.IntlRateV2Request('USERID' => @options[:login]) do
          xml.Revision(2)
          Array(packages).each_with_index do |package, id|
            xml.Package('ID' => id) do
              xml.Pounds(0)
              xml.Ounces([package.ounces, 1].max.ceil) # takes an integer for some reason, must be rounded UP
              xml.MailType(MAIL_TYPES[package.options[:mail_type]] || 'Package')
              xml.GXG do
                xml.POBoxFlag(destination.po_box? ? 'Y' : 'N')
                xml.GiftFlag(package.gift? ? 'Y' : 'N')
              end

              value = if package.value && package.value > 0 && package.currency && package.currency != 'USD'
                0.0
              else
                (package.value || 0) / 100.0
              end
              xml.ValueOfContents(value)

              xml.Country(country)
              xml.Container(package.cylinder? ? 'NONRECTANGULAR' : 'RECTANGULAR')
              xml.Size(USPS.size_code_for(package))
              xml.Width("%0.2f" % [package.inches(:width), 0.01].max)
              xml.Length("%0.2f" % [package.inches(:length), 0.01].max)
              xml.Height("%0.2f" % [package.inches(:height), 0.01].max)
              xml.Girth("%0.2f" % [package.inches(:girth), 0.01].max)
              xml.OriginZip(origin.zip)
              if commercial_type = commercial_type(options)
                xml.public_send(COMMERCIAL_FLAG_NAME.fetch(commercial_type), 'Y')
              end
              if destination.zip.present?
                xml.AcceptanceDateTime((options[:acceptance_time] || Time.now.utc).iso8601)
                xml.DestinationPostalCode(destination.zip)
              end
            end
          end
        end
      end
      save_request(xml_builder.to_xml)
    end

    def parse_rate_response(origin, destination, packages, response, options = {})
      success = true
      message = ''
      rate_hash = {}

      xml = Nokogiri.XML(response)

      if error = xml.at_xpath('/Error | //ServiceErrors/ServiceError')
        success = false
        message = error.at('Description').text
      else
        xml.root.xpath('Package').each do |package|
          if package.at('Error')
            success = false
            message = package.at('Error/Description').text
            break
          end
        end

        if success
          rate_hash = rates_from_response_node(xml, packages, options)
          unless rate_hash
            success = false
            message = "Unknown root node in XML response: '#{xml.root.name}'"
          end
        end

      end

      if success
        rate_estimates = rate_hash.keys.map do |service_name|
          RateEstimate.new(origin, destination, @@name, "USPS #{service_name}",
                           :package_rates => rate_hash[service_name][:package_rates],
                           :service_code => rate_hash[service_name][:service_code],
                           :currency => 'USD')
        end
        rate_estimates.reject! { |e| e.package_count != packages.length }
        rate_estimates = rate_estimates.sort_by(&:total_price)
      end

      RateResponse.new(success, message, Hash.from_xml(response), :rates => rate_estimates, :xml => response, :request => last_request)
    end

    def rates_from_response_node(response_node, packages, options = {})
      rate_hash = {}
      return false unless (root_node = response_node.at_xpath('/IntlRateV2Response | /RateV4Response'))

      commercial_type = commercial_type(options)
      service_node, service_code_node, service_name_node, rate_node = if root_node.name == 'RateV4Response'
        %w(Postage CLASSID MailService) << DOMESTIC_RATE_FIELD[commercial_type]
      else
        %w(Service ID SvcDescription)   << INTERNATIONAL_RATE_FIELD[commercial_type]
      end

      root_node.xpath('Package').each do |package_node|
        this_package = packages[package_node['ID'].to_i]

        package_node.xpath(service_node).each do |service_response_node|
          service_name = service_response_node.at(service_name_node).text

          service_name.gsub!(SERVICE_NAME_SUBSTITUTIONS, '')

          # aggregate specific package rates into a service-centric RateEstimate
          # first package with a given service name will initialize these;
          # later packages with same service will add to them
          this_service = rate_hash[service_name] ||= {}
          this_service[:service_code] ||= service_response_node.attributes[service_code_node].value
          package_rates = this_service[:package_rates] ||= []
          this_package_rate = {:package => this_package,
                               :rate => Package.cents_from(rate_value(rate_node, service_response_node, commercial_type))}

          package_rates << this_package_rate if package_valid_for_service(this_package, service_response_node)
        end
      end
      rate_hash
    end

    def package_valid_for_service(package, service_node)
      return true if service_node.at('MaxWeight').nil?
      max_weight = service_node.at('MaxWeight').text.to_f
      name = service_node.at_xpath('SvcDescription | MailService').text.downcase

      if name =~ /flat.rate.box/ # domestic or international flat rate box
        # flat rate dimensions from http://www.usps.com/shipping/flatrate.htm
        return (package_valid_for_max_dimensions(package,
                                                 :weight => max_weight, # domestic apparently has no weight restriction
                                                 :length => 11.0,
                                                 :width => 8.5,
                                                 :height => 5.5) or
               package_valid_for_max_dimensions(package,
                                                :weight => max_weight,
                                                :length => 13.625,
                                                :width => 11.875,
                                                :height => 3.375))
      elsif name =~ /flat.rate.envelope/
        return package_valid_for_max_dimensions(package,
                                                :weight => max_weight,
                                                :length => 12.5,
                                                :width => 9.5,
                                                :height => 0.75)
      elsif service_node.at('MailService') # domestic non-flat rates
        return true
      else # international non-flat rates
        # Some sample english that this is required to parse:
        #
        # 'Max. length 46", width 35", height 46" and max. length plus girth 108"'
        # 'Max. length 24", Max. length, height, depth combined 36"'
        #
        sentence = CGI.unescapeHTML(service_node.at('MaxDimensions').text)
        tokens = sentence.downcase.split(/[^\d]*"/).reject(&:empty?)
        max_dimensions = {:weight => max_weight}
        single_axis_values = []
        tokens.each do |token|
          axis_sum = [/length/, /width/, /height/, /depth/].sum { |regex| (token =~ regex) ? 1 : 0 }
          unless axis_sum == 0
            value = token[/\d+$/].to_f
            if axis_sum == 3
              max_dimensions[:length_plus_width_plus_height] = value
            elsif token =~ /girth/ and axis_sum == 1
              max_dimensions[:length_plus_girth] = value
            else
              single_axis_values << value
            end
          end
        end
        single_axis_values.sort!.reverse!
        [:length, :width, :height].each_with_index do |axis, i|
          max_dimensions[axis] = single_axis_values[i] if single_axis_values[i]
        end
        package_valid_for_max_dimensions(package, max_dimensions)
      end
    end

    def package_valid_for_max_dimensions(package, dimensions)
      ((not ([:length, :width, :height].map { |dim| dimensions[dim].nil? || dimensions[dim].to_f >= package.inches(dim).to_f }.include?(false))) and
              (dimensions[:weight].nil? || dimensions[:weight] >= package.pounds) and
              (dimensions[:length_plus_girth].nil? or
                  dimensions[:length_plus_girth].to_f >=
                  package.inches(:length) + package.inches(:girth)) and
              (dimensions[:length_plus_width_plus_height].nil? or
                  dimensions[:length_plus_width_plus_height].to_f >=
                  package.inches(:length) + package.inches(:width) + package.inches(:height)))
    end

    def parse_tracking_response(response, options = {})
      xml = Nokogiri.XML(response)

      if has_error?(xml)
        message = error_description_node(xml).text
        # actually raises instead of returning by nature of TrackingResponse#initialize
        return TrackingResponse.new(false, message, Hash.from_xml(response),
          carrier: @@name, xml: response, request: last_request)
      end

      # Responses are always returned in the order originally given.
      if options[:fault_tolerant]
        xml.root.xpath('TrackInfo').map do |info|
          # Don't let one failure wreck the whole batch
          begin
            parse_tracking_info(response, info)
          rescue ResponseError => e
            e.response
          end
        end
      else
        xml.root.xpath('TrackInfo').map { |info| parse_tracking_info(response, info) }
      end
    end

    def parse_tracking_info(response, node)
      success = !has_error?(node)
      message = response_message(node)

      if success
        destination = nil
        shipment_events = []
        tracking_details = node.xpath('TrackDetail')
        tracking_details << node.at('TrackSummary')

        tracking_number = node.attributes['ID'].value
        prediction_node = node.at('PredictedDeliveryDate') || node.at('ExpectedDeliveryDate')
        scheduled_delivery = prediction_node ? Time.parse(prediction_node.text) : nil

        tracking_details.each do |event|
          details = extract_event_details(event)
          if details.location
            shipment_events << ShipmentEvent.new(details.description, details.zoneless_time,
              details.location, details.description, details.event_code)
          end
        end

        shipment_events = shipment_events.sort_by(&:time)

        attempted_delivery_date = shipment_events.detect{ |shipment_event| ATTEMPTED_DELIVERY_CODES.include?(shipment_event.type_code) }.try(:time)

        if last_shipment = shipment_events.last
          status = last_shipment.status
          actual_delivery_date = last_shipment.time if last_shipment.delivered?
        end
      end

      TrackingResponse.new(success, message, Hash.from_xml(response),
                           :carrier => @@name,
                           :xml => response,
                           :request => last_request,
                           :shipment_events => shipment_events,
                           :destination => destination,
                           :tracking_number => tracking_number,
                           :status => status,
                           :actual_delivery_date => actual_delivery_date,
                           :attempted_delivery_date => attempted_delivery_date,
                           :scheduled_delivery_date => scheduled_delivery
      )
    end

    def error_description_node(node)
      node.xpath('Error/Description')
    end

    def response_status_node(node)
      node.at('StatusSummary') || error_description_node(node)
    end

    def has_error?(node)
      node.xpath('Error').length > 0
    end

    def response_message(document)
      response_status_node(document).text
    end

    def find_country_code_case_insensitive(name)
      upcase_name = name.upcase.gsub('  ', ', ')
      if special = TRACKING_ODD_COUNTRY_NAMES[upcase_name]
        return special
      end
      country = ActiveUtils::Country::COUNTRIES.detect { |c| c[:name].upcase == upcase_name }
      raise ActiveShipping::Error, "No country found for #{name}" unless country
      country[:alpha2]
    end

    def commit(action, request, test = false)
      ssl_get(request_url(action, request, test))
    end

    def request_url(action, request, test)
      scheme = USE_SSL[action] ? 'https://' : 'http://'
      host = DOMAINS[action][test ? :test : :live]
      "#{scheme}#{host}/#{RESOURCE}?API=#{API_CODES[action]}&XML=#{URI.encode(request)}"
    end

    def strip_zip(zip)
      zip.to_s.scan(/\d{5}/).first || zip
    end

    def strip_zip4(zip)
      zip.to_s.scan(/\d{4}/).first
    end

    def strip_phone(phone)
      # international API requires phone to be 10 digits
      # so return last 10 digits from the phone number
      phone.gsub('-', '').scan(/\d{10}$/).first
    end

    private

    def rate_value(rate_node, service_response_node, commercial_type)
      service_response_node.at(rate_node).try(:text).to_f
    end

    def commercial_type(options)
      if options[:commercial_plus] == true
        :plus
      elsif options[:commercial_base] == true
        :base
      end
    end
  end
end
