class OpenSocialApi
  def initialize(requester, request=nil)
    container = {
      :endpoint     => AppResources[:api_endpoint],
      :content_type => 'application/json',
      :rest         => '',
    }
    
    if requester.is_a?(User)
      requester_id = requester.id.to_s
    else
      requester_id = requester.to_s
    end
    
    oauth_token = OAuth::Token.new('', '')
    if AppResources.mbga? && request
      request_proxy = OAuth::RequestProxy.proxy(request)
      oauth_token = OAuth::Token.new(request_proxy.parameters["oauth_token"], request_proxy.parameters["oauth_token_secret"])
    end
    @connection = OpenSocial::Connection.new(:container => container,
                                 :consumer_key => AppResources[:consumer_key],
                                 :consumer_secret => AppResources[:consumer_secret],
                                 :consumer_token => oauth_token,
                                 :xoauth_requestor_id => requester_id)
  end
  
  def get_person(guid = '@me', selector = '@self', options = {})
    if AppResources.mbga? && options[:format].nil?
      options[:format] = 'json'
    end
    p = OpenSocial::FetchPersonRequest.new(@connection, guid, selector, options).send
    convert_person(parse_json(p.to_json))
  end
  
  def get_people(guid = '@me', selector = '@friends', options = {})
    p = OpenSocial::FetchPeopleRequest.new(@connection, guid, selector, options).send
    data = parse_json(p.to_json)
    data.each do |k, v|
      data[k] = convert_person(v)
    end
    data.values
  end
  
  def get_activities(guid = '@me', selector = '@self', pid = '@app', options = {})
    a = OpenSocial::FetchActivityRequest.new(@connection, guid, selector, pid, options).send
    parse_json(a.to_json)
  end

  def get_appdata(guid = '@me', selector = '@self', aid = '@app', options = {})
    a = OpenSocial::FetchAppDataRequest.new(@connection, guid, selector, pid, options).send
    parse_json(a.to_json)
  end
  
  def post_activity(data)
    OpenSocial::PostActivityRequest.new(@connection).send(data.to_json) if data
  end
  
  def post_appdata(data)
    OpenSocial::PostAppDataRequest.new(@connection).send(data.to_json) if data
  end
  
  def self.register(owner_id, request=nil)
    return if !owner_id
    
    api = self.new(owner_id, request)
    user_data = api.get_person('@me', '@self', {:fields => "id,nickname,profileUrl,thumbnailUrl,addresses,birthday,gender"})
    friends_data = api.get_people('@me', '@friends', {:count => 1000, :fields => "id,nickname,profileUrl,thumbnailUrl,addresses,birthday,gender"})
    
    user = User.cache_find_by_owner_id(user_data["owner_id"])
    user = User.new if !user
    user.attributes = user_data
    
    friends = []
    friends_data.each do |friend_data|
      next if !friend_data || !friend_data["nickname"] 
      friend = Friend.new(friend_data)
      if friend.has_app
        friend_user = User.cache_find_by_owner_id(friend_data["owner_id"])
        if friend_user.nil?
          friend.has_app = false
        end
      end
      friends << friend
    end
    user.friends = friends
    
    user.logged_at = Time.current
    if user.joined_at.nil?
      user.joined_at = Time.current
      
      app_invites = AppInvite.find_all_by_invitee_owner_id(owner_id)
      app_invites.each do |app_invite|
        app_invite.invite_status = AppInvite::INVITE_STATUS_INSTALLED
        app_invite.save
      end
    end
    user.save
  end
  
  def self.register_invite(owner_id, invite_owner_ids)
    invite_owner_ids.each do |invite_owner_id|
      app_invite = AppInvite.find_or_initialize_by_owner_id_and_invitee_owner_id(owner_id, invite_owner_id)
      app_invite.invite_status = AppInvite::INVITE_STATUS_INVITED
      app_invite.save
    end
  end
  
  protected
  def parse_json(data)
    data.is_a?(Hash) ? data : JSON.parse(data, :create_additions => false)
  end
  
  def convert_person(hash)
    {
      'owner_id' => hash['id'].split(':').last,
      'nickname' => hash['nickname'],
      'thumbnail_url' => hash['thumbnail_url'],
      'has_app' => hash['has_app'] == "true",
      'address' => (hash['addresses'] && hash['addresses'][0] && hash['addresses'][0]['address'] ? hash['addresses'][0]['address']['region'] : nil),
      'birthday' => hash['birthday'] ? Date.parse(hash['birthday']) : nil,
      'gender' => hash['gender'],
    }
  end
end
