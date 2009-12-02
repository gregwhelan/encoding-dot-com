require 'nokogiri'
require 'parsedate'
require 'ostruct'

module EncodingDotCom
  # A remote facade to the encoding.com API.
  #
  # The facade is stateless and can be reused for multiple requests.
  class Facade
    # Where encoding.com expects messages to be posted to.
    ENDPOINT = "http://manage.encoding.com/"

    # Creates a new facacde given an encoding.com user id & key, and
    # an HTTP library implementation.
    #
    # +http+ should respond to post, and return an object responding to
    # +#code+ and +#to_s+
    def initialize(user_id, user_key, http)
      @user_id, @user_key, @http = user_id, user_key, http
    end

    # Add a video/image to the encoding.com queue to be encoded in
    # various formats.
    #
    # Source is the source url
    # formats is a hash of destination urls => format objects
    def add_and_process(source, formats={})
      query = build_query("AddMedia") do |q|      
        q.source source
        formats.each {|url, format| format.build_xml(q, url) }
      end
      media_id = make_request(query.to_xml).xpath("/response/MediaID").text
      media_id.to_i if media_id
    end

    # Returns the status string of a particular media item in the
    # encoding.com queue. The status will be for the job as a whole,
    # rather than individual ouput formats
    def status(media_id)
      query = build_query("GetStatus") do |q|
        q.mediaid media_id
      end
      make_request(query.to_xml).xpath("/response/status").text
    end

    # Returns a list of media in the encoding.com queue
    def list
      query = build_query("GetMediaList")
      make_request(query.to_xml).xpath("/response/media").map do |node|
        attributes = OpenStruct.new
        attributes.mediafile = (node / "mediafile").text
        attributes.mediaid = (node / "mediaid").text.to_i
        attributes.mediastatus = (node / "mediastatus").text
        attributes.createdate = parse_time_node(node / "createdate")
        attributes.startdate = parse_time_node(node / "startdate")
        attributes.finishdate = parse_time_node(node / "finishdate")
        attributes
      end
    end

    private

    def parse_time_node(node)
      Time.local *ParseDate.parsedate(node.text)
    end
    
    def build_query(action)
      query = Nokogiri::XML::Builder.new do |q|
        q.query {
          q.userid @user_id
          q.userkey @user_key
          q.action action
          yield q if block_given?
        }
      end
    end
    
    def make_request(xml)
      response = @http.post(ENDPOINT, :xml => xml)
      raise AvailabilityError.new unless response.code.to_s == "200"
      xml = Nokogiri::XML(response.to_s)
      check_for_response_errors(xml)
      xml
    end

    def check_for_response_errors(xml)
      errors = xml.xpath("/response/errors/error").map {|e| e.text }
      raise MessageError.new(errors.join(", ")) unless errors.empty?
    end
  end
end
