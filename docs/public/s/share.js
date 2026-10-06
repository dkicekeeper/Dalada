// Страница «Поделиться» Dalada: место (/p/<id>/ или ?place=<id>), поездка (?trip=<id>), улов (?catch=<id>).
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
      open: "Открыть в Dalada", route: "Маршрут", getApp: "Как попасть в бету Dalada",
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
      open: "Dalada-да ашу", route: "Бағыт", getApp: "Dalada бетасына қалай қосылуға болады",
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
      open: "Open in Dalada", route: "Directions", getApp: "How to join the Dalada beta",
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
    var kinds = ["place", "trip", "catch"];
    for (var i = 0; i < kinds.length; i++) {
      var value = params.get(kinds[i]);
      if (value && uuid.test(value)) return { kind: kinds[i], id: value.toLowerCase() };
    }
    return null;
  })();

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
    links.push(el("a", { class: "button", href: base, text: T.getApp }));
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

  function renderPlace(place, photo) {
    setTitle(place.name);
    var nodes = [];
    if (photo) nodes.push(el("img", { class: "photo", src: photo, alt: "" }));
    nodes.push(el("h1", { text: place.name }));
    nodes.push(el("p", { class: "sub", text: T.types[place.type] || "" }));
    if (place.description) nodes.push(el("p", { class: "desc", text: place.description }));
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
    try {
      return new Date(value).toLocaleDateString(lang === "kk" ? "kk-KZ" : lang, { day: "numeric", month: "long", year: "numeric" });
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

  if (!target) {
    location.replace(base);
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
      rpc("place_editorial_photos", { p_place: target.id }).catch(function () { return null; })
    ]).then(function (results) {
      var place = results[0];
      if (!place || place.visibility !== "public") return message(T.notFound, T.notFoundHint);
      var editorial = results[1];
      var photo = editorial && editorial.path && config.photos ? config.photos + "/" + editorial.path : null;
      renderPlace(place, photo);
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
