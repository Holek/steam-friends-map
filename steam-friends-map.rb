require 'open-uri'
require 'json'
require 'net/http'
begin
  require 'sinatra'
rescue LoadError
  require 'rubygems'
  require 'sinatra'
end
# at this point rubygems is available
require 'omniauth'
require 'omniauth-steam-nitrogs'
require 'steam_location'



STATES = ["Offline", "Online",  "Busy", "Away", "Snooze", "Looking to trade", "Looking to play"]

use Rack::Session::Cookie
use OmniAuth::Builder do
  provider :steam, ENV['STEAM_WEB_API_KEY']
end

error OpenURI::HTTPError do
  if request.env['omniauth.auth']
    "Oi! Didn't I say your profile must be public? Change your <a href=\"http://steamcommunity.com/profiles/#{request.env['omniauth.auth'][:uid]}/edit/settings\">Steam privacy settings</a>, <a href=\"/\">go back and try again</a>!"
  else
    'Bad things happen'
  end
end

get '/' do
  <<-HTML
<!DOCTYPE html>
<html>
<head>
  <title>Steam Friends' Map - Sign in</title>
</head>
<body>
  <a href='/auth/steam'><img src="http://cdn.steamcommunity.com/public/images/signinthroughsteam/sits_small.png" /></a><br/>

  <strong>Your profile must be public for this map to work!</strong>

  <h4> Policy information </h4>
  <ul>
    <li>This site will never store any information about you or your Steam friends.</li>
    <li>Upon sign in you will be presented with a map, and we will fetch information about all your friends to show them for you on a map.</li>
    <li>This site does not store any cookies.</li>
    <li>Sign in is one-time, meaning you will have to log in every time you visit this page.</li>
    <li>This site is open-source, and its code <a href="https://github.com/Holek/steam-friends-map">is available on GitHub</a>.</li>
  </ul>
</body>
</html>
  HTML
end

post '/auth/:name/callback' do
  auth = request.env['omniauth.auth']

  friend_ids = get_friends(auth[:uid])
  friend_details = get_friends_details(friend_ids)
  index = 0
  javascript_markers = []
  javascript_unkown_markers = []
  friend_details.each do |location_string, friend_group|
    if coordinates = friend_group.first[:coordinates]
      javascript_markers << <<-JS
window.markers.push(new google.maps.Marker({
  icon: "#{friend_group.first['avatar']}",
  shadow: {
    anchor: steamProfileShadow,
    url: 'http://img.poltyn.com/maps_shadow#{'_online' unless friend_group.first['personastate'].zero?}.png'
  },
  position: new google.maps.LatLng(#{coordinates})
}));
JS
    else
      javascript_unkown_markers << <<-JS
  setTimeout("window.geocoder.geocode( { 'address': '#{location_string.sub('\'','\\\'')}'}, window.placeMarker)", #{index*500});
JS
    index += 1
    end
  end

  user = SteamLocation.find(*(auth['info']['location'].split(', ').reverse)) unless auth['info']['location'].empty?
  if user && user[:coordinates]
    user_location_js = <<-JS
    var user_location = new google.maps.LatLng(#{user[:coordinates]});
    window.map.setCenter(user_location);
    var marker = new google.maps.Marker({
        map: window.map,
        position: user_location
    });
JS
  else
    user_location_js = <<-JS
  var player_location = '#{auth['info']['location']}',
  player_location_coord;
  window.geocoder.geocode( { 'address': player_location}, function(results, status) {
    if (status == google.maps.GeocoderStatus.OK) {
      window.map.setCenter(results[0].geometry.location);
      new google.maps.Marker({
        map: window.map,
        position: results[0].geometry.location
      });
    }
  });
JS
  end

  html = <<-HTML
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="initial-scale=1.0, user-scalable=no" />
<script type="text/javascript" src="https://maps.googleapis.com/maps/api/js?key=#{ENV['GOOGLE_API_KEY']}&sensor=false"></script>
<script type="text/javascript" src="http://google-maps-utility-library-v3.googlecode.com/svn/trunk/markerclusterer/src/markerclusterer_compiled.js"></script>
<style type="text/css">
html{height:100%}
body{height:100%;margin:0;padding:0}
  #map_canvas { height: 100% }
</style>
</head>
<body>
<div id="map_canvas" style="width:100%; height:100%"></div>

<script type="text/javascript">
function initialize() {
  steamProfileShadow = new google.maps.Point(20,36)
  window.geocoder = new google.maps.Geocoder();
  var mapOptions = {
    center: new google.maps.LatLng(0, 0),
    zoom: 3,
    mapTypeId: google.maps.MapTypeId.ROADMAP
  }
    , map_canvas = document.getElementById("map_canvas");
  window.map = new google.maps.Map(map_canvas, mapOptions);
  #{user_location_js}
  window.markers = []
  window.placeMarker = function(results, status) {
    if (status == google.maps.GeocoderStatus.OK)
      window.markers.push(new google.maps.Marker({position: results[0].geometry.location}));
  };
  #{javascript_markers.join}
  #{javascript_unkown_markers.join}
  setTimeout('new MarkerClusterer(window.map, window.markers);', #{index*500});
}
window.onload = initialize;
</script>
</body>
</html>
HTML

# Hello, #{auth["info"]["nickname"]}.<br/>
# <img src="#{auth['info']['image']}" />
# You have #{friend_ids.size} friends. #{friend_details.size} of them filled their location data.

  html
end


def get_friends(steamID64)
  friends = JSON.parse(open("https://api.steampowered.com/ISteamUser/GetFriendList/v0001/?key=#{ENV['STEAM_WEB_API_KEY']}&steamid=#{steamID64}&relationship=friend&format=json").read)
  friends["friendslist"]["friends"].map{|friend|friend["steamid"]}
end

def get_friends_details(friend_ids_original)
  ignored_keys = %w(lastlogoff avatarfull primaryclanid timecreated)
  friend_ids = friend_ids_original.clone
  friend_info = []
  # the API handles up to 100 steam IDs at the time
  while !(current_friends_ids = friend_ids.pop(100)).empty?
    url = URI.parse("https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key=#{ENV['STEAM_WEB_API_KEY']}&steamids=#{current_friends_ids.join(',')}")
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(url.request_uri)

    response = http.request(request)
    friend_info += JSON.parse(response.body)["response"]["players"]
  end
  friend_info.delete_if{|friend| friend["loccityid"].nil? && friend["locstatecode"].nil? && friend["loccountrycode"].nil? }
  friend_groups = {}
  friend_info.each do |friend|
    ignored_keys.each { |k| friend.delete(k)}
    friend.merge!(SteamLocation.find(friend))
    # Ruby doesn't have Array#group... WTF?
    friend_group = friend[:coordinates] || friend[:map_search_string]
    friend_groups[friend_group] ||= []
    friend_groups[friend_group] << friend
  end
  friend_groups
end

