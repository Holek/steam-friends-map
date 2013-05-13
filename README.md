# Steam Friends' Map

![Example map](http://img.poltyn.com/steam-map-20130513-200851.png)

This app has been developed to show all your friends' locations from [Steam Community](http://steamcommunity.com). Steam has a great social network for gamers, but it lacks in showing global information about players.

It is available under: [steam-map.herokuapp.com](http://steam-map.herokuapp.com/)

### Terms, under which this website works

**Your Steam profile must be public for this map to work!** That is a requirement for now, due to how Steam OpenID is implemented. If you try to login with a private profile, you will be prompted to change your settings, and log in again.

* This site will never store any information about you or your Steam friends.
* Upon sign in you will be presented with a map, and we will fetch information about all your friends to show them for you on a map.
* This site does not store any cookies.
* Sign in is one-time, meaning you will have to log in every time you visit this page.

### Other treats

This application uses another Steam library, [`steam-friends-countries` a.k.a. `steam_location` gem](http://github.com/Holek/steam-friends-countries), which is responsible for geolocating results from Steam Community Web API. Go check it out, if you have similar projects.

### License
Code is released under MIT License
