// Страница «Поделиться» Dalada: место (/p/<id>/ или ?place=<id>), поездка (?trip=<id>), улов (?catch=<id>),
// приглашение в поездку (?invite=<токен>) и в друзья (?u=<ник>).
// Данные — ключом гостя через RPC web_trip, web_catch, place_card: только публичное. Текст из базы
// вставляем только как textContent (никакого innerHTML с данными).
(function () {
  "use strict";

  var config = window.DALADA || {};
  var base = window.DALADA_BASE || "/";
  var app = document.getElementById("app");
  var lang = (function () {
    var list = (navigator.languages || [navigator.language || "ru"]).map(function (l) { return String(l).toLowerCase(); });
    for (var i = 0; i < list.length; i++) {
      if (list[i].indexOf("kk") === 0) return "kk";
      if (list[i].indexOf("ru") === 0) return "ru";
      if (list[i].indexOf("en") === 0) return "en";
    }
    return "ru";
  })();
  document.documentElement.lang = lang;

  var T = {
    ru: {
      open: "Открыть в Dalada", route: "Маршрут", getApp: "Как попасть в бету Dalada", getAppStore: "Скачать Dalada в App Store",
      invite: "Вас зовут в поездку", inviteHint: "Установите Dalada, войдите и откройте эту ссылку в приложении — вы станете участником поездки.",
      inviteJoin: "Присоединиться в Dalada",
      friend: "Вас зовут в Dalada", friendOpen: "Открыть профиль в Dalada",
      friendHint: "Установите Dalada, войдите и откройте эту ссылку ещё раз — откроется профиль, и его можно будет добавить в друзья.",
      about: "Dalada — карта рыбалки и отдыха на природе по всему Казахстану: места, свежие отчёты, запреты на лов и карта без сети. Бесплатно, для iPhone.",
      notFound: "Запись недоступна", notFoundHint: "Её удалили или она видна не всем. Откройте ссылку в приложении Dalada.",
      failed: "Не удалось загрузить", failedHint: "Проверьте интернет и обновите страницу.",
      approximate: "Место показано приблизительно — в радиусе около километра.",
      distance: "км", time: "в движении", elevation: "м набора", weight: "вес", length: "длина",
      released: "Отпустил", reviews: "отзывов", by: "Автор",
      types: { base: "База отдыха", campsite: "Стоянка", fishing_spot: "Точка ловли", landmark: "Достопримечательность",
        paid_pond: "Платник", parking: "Съезд, парковка", spring: "Родник", tackle_shop: "Снасти и наживка", water_body: "Водоём" },
      activities: { fishing: "Рыбалка", camping: "Кемпинг", hiking: "Поход", other: "Поездка" },
      hours: "ч", minutes: "мин", kg: "кг", g: "г", cm: "см"
    },
    kk: {
      open: "Dalada-да ашу", route: "Бағыт", getApp: "Dalada бетасына қалай қосылуға болады", getAppStore: "Dalada-ны App Store-дан жүктеу",
      invite: "Сізді сапарға шақырады", inviteHint: "Dalada-ны орнатып, кіріңіз де, осы сілтемені қосымшада ашыңыз — сапарға қатысушы боласыз.",
      inviteJoin: "Dalada-да қосылу",
      friend: "Сізді Dalada-ға шақырады", friendOpen: "Профильді Dalada-да ашу",
      friendHint: "Dalada-ны орнатып, кіріңіз де, осы сілтемені қайта ашыңыз — профиль ашылады, оны досқа қоса аласыз.",
      about: "Dalada — бүкіл Қазақстан бойынша балық аулау мен табиғаттағы демалыс картасы: орындар, жаңа есептер, аулауға тыйымдар және байланыссыз карта. Тегін, iPhone үшін.",
      notFound: "Жазба қолжетімсіз", notFoundHint: "Ол жойылған немесе барлығына көрінбейді. Сілтемені Dalada қосымшасында ашыңыз.",
      failed: "Жүктеу мүмкін болмады", failedHint: "Интернетті тексеріп, бетті жаңартыңыз.",
      approximate: "Орын шамамен көрсетілген — шамамен бір шақырым радиуста.",
      distance: "км", time: "қозғалыста", elevation: "м көтерілу", weight: "салмағы", length: "ұзындығы",
      released: "Босатылды", reviews: "пікір", by: "Авторы",
      types: { base: "Демалыс базасы", campsite: "Тұрақ", fishing_spot: "Балық аулайтын жер", landmark: "Көрікті жер",
        paid_pond: "Ақылы тоған", parking: "Көлік тұрағы", spring: "Бұлақ", tackle_shop: "Балық аулау құралдары", water_body: "Су айдыны" },
      activities: { fishing: "Балық аулау", camping: "Кемпинг", hiking: "Жаяу серуен", other: "Сапар" },
      hours: "сағ", minutes: "мин", kg: "кг", g: "г", cm: "см"
    },
    en: {
      open: "Open in Dalada", route: "Directions", getApp: "How to join the Dalada beta", getAppStore: "Get Dalada on the App Store",
      invite: "You’re invited on a trip", inviteHint: "Install Dalada, sign in and open this link in the app — you’ll join the trip.",
      inviteJoin: "Join in Dalada",
      friend: "You’re invited to Dalada", friendOpen: "Open the profile in Dalada",
      friendHint: "Install Dalada, sign in and open this link again — the profile opens and you can add them as a friend.",
      about: "Dalada is a map for fishing and the outdoors across Kazakhstan: places, fresh reports, fishing bans and an offline map. Free, for iPhone.",
      notFound: "Not available", notFoundHint: "It was deleted or isn’t visible to everyone. Open the link in the Dalada app.",
      failed: "Couldn’t load", failedHint: "Check your connection and reload the page.",
      approximate: "The place is shown approximately, within about a kilometre.",
      distance: "km", time: "moving", elevation: "m climb", weight: "weight", length: "length",
      released: "Released", reviews: "reviews", by: "By",
      types: { base: "Holiday camp", campsite: "Campsite", fishing_spot: "Fishing spot", landmark: "Landmark",
        paid_pond: "Paid pond", parking: "Parking", spring: "Spring", tackle_shop: "Tackle and bait", water_body: "Water body" },
      activities: { fishing: "Fishing", camping: "Camping", hiking: "Hiking", other: "Trip" },
      hours: "h", minutes: "min", kg: "kg", g: "g", cm: "cm"
    }
  }[lang];

  // Что открыто: путь /p/<id>/ (статическая страница места) или ?place= / ?trip= / ?catch=.
  var uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  var target = (function () {
    var match = location.pathname.match(/\/p\/([0-9a-f-]{36})\/?$/i);
    if (match && uuid.test(match[1])) return { kind: "place", id: match[1].toLowerCase() };
    var params = new URLSearchParams(location.search);
    var invite = params.get("invite");
    if (invite && /^[0-9a-f]{32}$/.test(invite)) return { kind: "invite", id: invite };
    // Ник — по правилам приложения (UsernameRules): 3–30 символов, латиница, цифры, «_» и «.».
    var username = (params.get("u") || "").trim().toLowerCase();
    if (/^[a-z0-9_.]{3,30}$/.test(username)) return { kind: "friend", id: username };
    var kinds = ["place", "trip", "catch"];
    for (var i = 0; i < kinds.length; i++) {
      var value = params.get(kinds[i]);
      if (value && uuid.test(value)) return { kind: kinds[i], id: value.toLowerCase() };
    }
    return null;
  })();

  // Метка кампании App Store Connect (ct) по виду страницы — видно, сколько установок дали ссылки
  // каждого вида (docs/05-release/promotion.md, «Метки кампаний»). Только суммы, без слежки.
  var campaigns = { place: "site-place", trip: "site-share", "catch": "site-share", invite: "trip-invite", friend: "invite" };

  // Своя метка из адреса страницы — для QR-табличек и постов: …/p/<id>/?ct=qr-<место>.
  var urlCampaign = (function () {
    var value = new URLSearchParams(location.search).get("ct");
    return value && /^[a-z0-9-]{1,30}$/.test(value) ? value : null;
  })();

  function appStoreURL() {
    if (!config.appStorePt) return config.appStore;
    var campaign = urlCampaign || (target && campaigns[target.kind]) || "site-share";
    return config.appStore + "?pt=" + encodeURIComponent(config.appStorePt) + "&ct=" + campaign;
  }

  // До выхода — как попасть в бету (главная сайта), после — App Store (config.appStore).
  function getAppLink() {
    return config.appStore
      ? el("a", { class: "button", href: appStoreURL(), text: T.getAppStore })
      : el("a", { class: "button", href: base, text: T.getApp });
  }

  function el(tag, attrs, children) {
    var node = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (key) {
      if (key === "text") node.textContent = attrs[key];
      else if (key === "class") node.className = attrs[key];
      else node.setAttribute(key, attrs[key]);
    });
    (children || []).forEach(function (child) { if (child) node.appendChild(child); });
    return node;
  }

  function rpc(name, args) {
    return fetch(config.url + "/rest/v1/rpc/" + name, {
      method: "POST",
      headers: { apikey: config.key, Authorization: "Bearer " + config.key, "Content-Type": "application/json" },
      body: JSON.stringify(args)
    }).then(function (response) {
      if (!response.ok) throw new Error("HTTP " + response.status);
      return response.json();
    }).then(function (rows) { return Array.isArray(rows) ? rows[0] : rows; });
  }

  // Фото из закрытого бакета: временная ссылка (политика хранилища пускает гостя к фото публичных записей).
  function signedPhoto(path) {
    if (!path) return Promise.resolve(null);
    return fetch(config.url + "/storage/v1/object/sign/media/" + path.split("/").map(encodeURIComponent).join("/"), {
      method: "POST",
      headers: { apikey: config.key, Authorization: "Bearer " + config.key, "Content-Type": "application/json" },
      body: JSON.stringify({ expiresIn: 3600 })
    }).then(function (response) { return response.ok ? response.json() : null; })
      .then(function (body) { return body && body.signedURL ? config.url + "/storage/v1" + body.signedURL : null; })
      .catch(function () { return null; });
  }

  function show(nodes) {
    app.textContent = "";
    nodes.forEach(function (node) { if (node) app.appendChild(node); });
  }

  function message(title, hint) {
    show([el("div", { class: "empty" }, [el("h1", { text: title }), el("p", { class: "muted", text: hint })]), appActions(null)]);
  }

  function appActions(deepLink, extra) {
    var links = [];
    if (deepLink) links.push(el("a", { class: "button primary", href: deepLink, text: T.open }));
    (extra || []).forEach(function (link) { links.push(link); });
    links.push(getAppLink());
    return el("div", { class: "actions" }, links);
  }

  function fact(value, label) {
    return el("div", { class: "fact" }, [el("b", { text: value }), el("span", { text: label })]);
  }

  function setTitle(text) { if (text) document.title = text + " — Dalada"; }

  function map(setup) {
    var node = el("div", { id: "map" });
    if (!window.maplibregl) return null;
    setTimeout(function () {
      var instance = new window.maplibregl.Map({
        container: node,
        style: "https://tiles.openfreemap.org/styles/liberty",
        attributionControl: { compact: true },
        cooperativeGestures: true
      });
      instance.on("load", function () { setup(instance); });
    }, 0);
    return node;
  }

  // Круг радиусом `meters` вокруг точки — для приблизительного места.
  function circle(lon, lat, meters) {
    var points = [];
    for (var i = 0; i <= 64; i++) {
      var angle = (i / 64) * 2 * Math.PI;
      var dLat = (meters / 111320) * Math.sin(angle);
      var dLon = (meters / (111320 * Math.cos(lat * Math.PI / 180))) * Math.cos(angle);
      points.push([lon + dLon, lat + dLat]);
    }
    return { type: "Feature", geometry: { type: "Polygon", coordinates: [points] } };
  }

  // Казахские названия месяцев есть не во всех браузерах — пишем сами: «2026 жылғы 6 қазан».
  var monthsKK = ["қаңтар", "ақпан", "наурыз", "сәуір", "мамыр", "маусым", "шілде", "тамыз", "қыркүйек", "қазан", "қараша", "желтоқсан"];

  // «Сведения» места — подписи как в приложении (Localizable.xcstrings, place.info.*).
  var INFO = {
    ru: {
      species: "Рыба", methods: "Способы ловли", access: "Подъезд", fee: "Стоимость", contact: "Контакты",
      amenities: "Удобства", signal: "Связь", months: "Лучшие месяцы", features: "Особенности",
      access_: { asphalt: "Асфальт", dirt: "Грунтовка", offroad: "Только на 4×4", foot: "Пешком", boat: "На лодке" },
      fee_: { free: "Бесплатно", paid: "Платно" },
      unit_: { entry: "за вход", day: "за сутки", hour: "в час", kg: "за кг улова" },
      methods_: { shore: "С берега", boat: "С лодки", spinning: "Спиннинг", feeder: "Фидер", float: "Поплавок",
        fly: "Нахлыст", bottom: "Донка", ice: "Со льда" },
      amenities_: { parking: "Парковка", toilet: "Туалет", shade: "Тень", tent: "Место под палатку",
        fireplace: "Костровище", drinking_water: "Питьевая вода", shop: "Магазин рядом", boat_rental: "Прокат лодок" },
      signal_: { none: "Нет", weak: "Слабая", good: "Хорошая" },
      months_: ["январь", "февраль", "март", "апрель", "май", "июнь", "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"]
    },
    kk: {
      species: "Балық", methods: "Аулау тәсілдері", access: "Жол", fee: "Құны", contact: "Байланыс",
      amenities: "Жайлылықтар", signal: "Байланыс сапасы", months: "Ең жақсы айлар", features: "Ерекшеліктері",
      access_: { asphalt: "Асфальт", dirt: "Топырақ жол", offroad: "Тек 4×4 көлігімен", foot: "Жаяу", boat: "Қайықпен" },
      fee_: { free: "Тегін", paid: "Ақылы" },
      unit_: { entry: "кіру үшін", day: "тәулігіне", hour: "сағатына", kg: "олжаның 1 кг үшін" },
      methods_: { shore: "Жағадан", boat: "Қайықтан", spinning: "Спиннинг", feeder: "Фидер", float: "Қалтқы",
        fly: "Нахлыст", bottom: "Түптік қармақ", ice: "Мұздан" },
      amenities_: { parking: "Тұрақ", toilet: "Дәретхана", shade: "Көлеңке", tent: "Шатыр орны",
        fireplace: "От жағатын орын", drinking_water: "Ауыз су", shop: "Жақын маңда дүкен", boat_rental: "Қайық жалға беру" },
      signal_: { none: "Жоқ", weak: "Әлсіз", good: "Жақсы" },
      months_: monthsKK
    },
    en: {
      species: "Fish", methods: "Fishing methods", access: "Access", fee: "Price", contact: "Contact",
      amenities: "Amenities", signal: "Mobile signal", months: "Best months", features: "Details",
      access_: { asphalt: "Paved road", dirt: "Dirt road", offroad: "4×4 only", foot: "On foot", boat: "By boat" },
      fee_: { free: "Free", paid: "Paid" },
      unit_: { entry: "per entry", day: "per day", hour: "per hour", kg: "per kg of catch" },
      methods_: { shore: "From shore", boat: "From a boat", spinning: "Spinning", feeder: "Feeder", float: "Float",
        fly: "Fly fishing", bottom: "Bottom rig", ice: "Ice fishing" },
      amenities_: { parking: "Parking", toilet: "Toilet", shade: "Shade", tent: "Tent pitch", fireplace: "Fire pit",
        drinking_water: "Drinking water", shop: "Shop nearby", boat_rental: "Boat rental" },
      signal_: { none: "None", weak: "Weak", good: "Good" },
      months_: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    }
  }[lang];
  var FISHING_TYPES = { fishing_spot: true, water_body: true, paid_pond: true };

  // Список как в предложении: «Сазан, карп, судак» — заглавная только первая буква.
  function asList(items) {
    items = items.filter(Boolean);
    return items.map(function (item, i) { return i === 0 ? item : item.charAt(0).toLowerCase() + item.slice(1); }).join(", ");
  }

  // Месяцы отрезками, как PlaceAttributes.monthSpans: [12, 1, 2] → [[12, 2]].
  function monthSpans(months) {
    var sorted = (months || []).filter(function (m, i, all) {
      return m >= 1 && m <= 12 && m % 1 === 0 && all.indexOf(m) === i;
    }).sort(function (a, b) { return a - b; });
    if (!sorted.length) return [];
    if (sorted.length === 12) return [[1, 12]];
    var spans = [[sorted[0], sorted[0]]];
    sorted.slice(1).forEach(function (m) {
      var last = spans[spans.length - 1];
      if (m === last[1] + 1) last[1] = m; else spans.push([m, m]);
    });
    if (spans.length > 1 && spans[0][0] === 1 && spans[spans.length - 1][1] === 12) {
      spans[spans.length - 1][1] = spans.shift()[1];
    }
    return spans;
  }

  // Строки «Сведений»: у мест для рыбалки сначала рыба и способы ловли — как в приложении.
  function infoRows(place, fish) {
    var info = place.attributes || {};
    function titles(key) {
      var names = INFO[key + "_"];
      return asList((info[key] || []).map(function (v) { return names[v]; }));
    }
    var fishing = [], other = [];
    var known = (info.species || []).filter(function (id) { return fish[id]; })
      .sort(function (a, b) { return fish[a].order - fish[b].order; })
      .map(function (id) { return fish[id].name; });
    if (known.length) fishing.push([INFO.species, asList(known)]);
    if (titles("methods")) fishing.push([INFO.methods, titles("methods")]);
    if (titles("access")) other.push([INFO.access, titles("access")]);
    var fee = INFO.fee_[info.fee];
    if (fee) {
      if (info.price_kzt > 0) {
        var unit = INFO.unit_[info.price_unit];
        fee += " · " + Number(info.price_kzt).toLocaleString(lang === "en" ? "en" : "ru") + " ₸" + (unit ? " " + unit : "");
      }
      other.push([INFO.fee, fee]);
    }
    if (typeof info.contact === "string" && info.contact.trim()) other.push([INFO.contact, info.contact.trim()]);
    if (titles("amenities")) other.push([INFO.amenities, titles("amenities")]);
    if (INFO.signal_[info.signal]) other.push([INFO.signal, INFO.signal_[info.signal]]);
    var months = monthSpans(info.months).map(function (span) {
      return span[0] === span[1] ? INFO.months_[span[0] - 1] : INFO.months_[span[0] - 1] + "–" + INFO.months_[span[1] - 1];
    }).join(", ");
    if (months) other.push([INFO.months, months.charAt(0).toUpperCase() + months.slice(1)]);
    if (typeof info.features === "string" && info.features.trim()) other.push([INFO.features, info.features.trim()]);
    return FISHING_TYPES[place.type] ? fishing.concat(other) : other.concat(fishing);
  }

  function infoList(rows) {
    if (!rows.length) return null;
    var children = [];
    rows.forEach(function (row) {
      children.push(el("dt", { text: row[0] }));
      children.push(el("dd", { text: row[1] }));
    });
    return el("dl", { class: "info" }, children);
  }

  // Справочник рыб на языке страницы: id → { name, order }. Не загрузился — без строки «Рыба».
  function fishNames() {
    var column = "name_" + lang;
    return fetch(config.url + "/rest/v1/fish_species?select=id,sort_order," + column, {
      headers: { apikey: config.key, Authorization: "Bearer " + config.key }
    }).then(function (response) { return response.ok ? response.json() : []; })
      .then(function (rows) {
        var names = {};
        (rows || []).forEach(function (row) { if (row[column]) names[row.id] = { name: row[column], order: row.sort_order || 0 }; });
        return names;
      })
      .catch(function () { return {}; });
  }

  function renderPlace(place, photo, fish) {
    // У статической страницы /p/<id>/ заголовок уже собран для поиска (build_site.py) — не трогаем.
    if (!/\/p\/[0-9a-f-]{36}\/?$/i.test(location.pathname)) setTitle(place.name);
    var nodes = [];
    if (photo) nodes.push(el("img", { class: "photo", src: photo, alt: "" }));
    nodes.push(el("h1", { text: place.name }));
    nodes.push(el("p", { class: "sub", text: T.types[place.type] || "" }));
    if (place.description) nodes.push(el("p", { class: "desc", text: place.description }));
    nodes.push(infoList(infoRows(place, fish || {})));
    nodes.push(map(function (instance) {
      var center = [place.lon, place.lat];
      if (place.approximate) {
        instance.addSource("area", { type: "geojson", data: circle(place.lon, place.lat, place.radius_m || 1000) });
        instance.addLayer({ id: "area", type: "fill", source: "area", paint: { "fill-color": "#1f7a5a", "fill-opacity": 0.2 } });
        instance.jumpTo({ center: center, zoom: 12 });
      } else {
        new window.maplibregl.Marker({ color: "#1f7a5a" }).setLngLat(center).addTo(instance);
        instance.jumpTo({ center: center, zoom: 13 });
      }
    }));
    if (place.approximate) nodes.push(el("p", { class: "note", text: T.approximate }));
    var extra = [];
    if (!place.approximate) {
      extra.push(el("a", {
        class: "button", text: T.route,
        href: "https://www.google.com/maps/dir/?api=1&destination=" + place.lat + "," + place.lon
      }));
    }
    nodes.push(appActions("dalada://place/" + place.id, extra));
    show(nodes);
  }

  function duration(seconds) {
    var hours = Math.floor(seconds / 3600);
    var minutes = Math.round((seconds % 3600) / 60);
    return hours > 0 ? hours + " " + T.hours + " " + minutes + " " + T.minutes : minutes + " " + T.minutes;
  }


  function day(value) {
    var date = new Date(value);
    if (isNaN(date.getTime())) return String(value).slice(0, 10);
    if (lang === "kk") return date.getFullYear() + " жылғы " + date.getDate() + " " + monthsKK[date.getMonth()];
    try {
      return date.toLocaleDateString(lang, { day: "numeric", month: "long", year: "numeric" });
    } catch (e) { return String(value).slice(0, 10); }
  }

  function author(row) {
    var name = row.author_name || (row.author_username ? "@" + row.author_username : "");
    return name ? T.by + ": " + name : "";
  }

  function renderTrip(trip) {
    setTitle(trip.title);
    var nodes = [
      el("h1", { text: trip.title }),
      el("p", { class: "sub", text: [T.activities[trip.activity] || "", day(trip.started_at), author(trip)].filter(Boolean).join(" · ") }),
      el("div", { class: "facts" }, [
        fact((trip.distance_m / 1000).toFixed(1), T.distance),
        fact(duration(trip.moving_seconds || 0), T.time),
        trip.elevation_gain_m > 0 ? fact(String(trip.elevation_gain_m), T.elevation) : null
      ])
    ];
    if (trip.track) {
      nodes.push(map(function (instance) {
        instance.addSource("track", { type: "geojson", data: { type: "Feature", geometry: trip.track } });
        instance.addLayer({ id: "track", type: "line", source: "track",
          paint: { "line-color": "#1f7a5a", "line-width": 4 }, layout: { "line-cap": "round", "line-join": "round" } });
        var bounds = new window.maplibregl.LngLatBounds();
        var lines = trip.track.type === "LineString" ? [trip.track.coordinates] : trip.track.coordinates;
        lines.forEach(function (line) { line.forEach(function (point) { bounds.extend(point); }); });
        if (!bounds.isEmpty()) instance.fitBounds(bounds, { padding: 32, duration: 0 });
      }));
    }
    nodes.push(appActions("dalada://trip/" + target.id));
    show(nodes);
  }

  function renderCatch(row, photo) {
    var species = row["species_" + lang] || row.species_ru || row.species_id;
    setTitle(species);
    var facts = [];
    if (row.weight_g) facts.push(fact(row.weight_g >= 1000 ? (row.weight_g / 1000).toFixed(1) + " " + T.kg : row.weight_g + " " + T.g, T.weight));
    if (row.length_mm) facts.push(fact(Math.round(row.length_mm / 10) + " " + T.cm, T.length));
    var nodes = [];
    if (photo) nodes.push(el("img", { class: "photo", src: photo, alt: "" }));
    nodes.push(el("h1", { text: species + (row.count > 1 ? " × " + row.count : "") }));
    nodes.push(el("p", { class: "sub", text: [row.place_name, day(row.caught_on), author(row), row.released ? T.released : ""].filter(Boolean).join(" · ") }));
    if (facts.length) nodes.push(el("div", { class: "facts" }, facts));
    nodes.push(appActions(row.place_id ? "dalada://place/" + row.place_id : "dalada://"));
    show(nodes);
  }

  // Приглашение в поездку: кто зовёт и куда; присоединиться — в приложении.
  function renderInvite(row) {
    setTitle(row.title);
    var who = row.owner_name || (row.owner_username ? "@" + row.owner_username : "");
    show([
      el("p", { class: "sub", text: T.invite }),
      el("h1", { text: row.title }),
      el("p", { class: "sub", text: [T.activities[row.activity] || "", day(row.started_at), who].filter(Boolean).join(" · ") }),
      el("p", { class: "desc", text: T.inviteHint }),
      el("div", { class: "actions" }, [
        el("a", { class: "button primary", href: "dalada://trip-invite/" + target.id, text: T.inviteJoin }),
        getAppLink()
      ])
    ]);
  }

  // Приглашение в друзья: только ник из ссылки, без запросов к базе (закрытый профиль не раскрываем).
  // Зовут чаще тех, у кого Dalada ещё нет, поэтому главная кнопка — App Store; у кого есть — «Открыть
  // профиль» (и «Открыть» в баннере Safari сверху).
  function renderFriend(username) {
    setTitle("@" + username);
    var store = getAppLink();
    store.className = "button primary";
    show([
      el("p", { class: "sub", text: T.friend }),
      el("h1", { text: "@" + username }),
      el("p", { class: "desc", text: T.about }),
      el("p", { class: "desc", text: T.friendHint }),
      el("div", { class: "actions" }, [
        store,
        el("a", { class: "button", href: "dalada://u/" + username, text: T.friendOpen })
      ])
    ]);
  }

  if (!target) {
    location.replace(base);
    return;
  }
  if (target.kind === "friend") {
    renderFriend(target.id);
    return;
  }
  if (!config.url || !config.key) {
    message(T.failed, T.failedHint);
    return;
  }

  var load;
  if (target.kind === "place") {
    load = Promise.all([
      rpc("place_card", { p_id: target.id }),
      rpc("place_editorial_photos", { p_place: target.id }).catch(function () { return null; }),
      fishNames()
    ]).then(function (results) {
      var place = results[0];
      if (!place || place.visibility !== "public") return message(T.notFound, T.notFoundHint);
      var editorial = results[1];
      var photo = editorial && editorial.path && config.photos ? config.photos + "/" + editorial.path : null;
      renderPlace(place, photo, results[2]);
    });
  } else if (target.kind === "invite") {
    load = rpc("web_trip_invite", { p_token: target.id }).then(function (row) {
      if (!row) return message(T.notFound, T.notFoundHint);
      renderInvite(row);
    });
  } else if (target.kind === "trip") {
    load = rpc("web_trip", { p_trip: target.id }).then(function (trip) {
      if (!trip) return message(T.notFound, T.notFoundHint);
      renderTrip(trip);
    });
  } else {
    load = rpc("web_catch", { p_catch: target.id }).then(function (row) {
      if (!row) return message(T.notFound, T.notFoundHint);
      return signedPhoto(row.photo_path).then(function (photo) { renderCatch(row, photo); });
    });
  }
  load.catch(function () { message(T.failed, T.failedHint); });
})();
