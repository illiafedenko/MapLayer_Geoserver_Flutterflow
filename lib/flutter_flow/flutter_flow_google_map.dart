// ignore_for_file: prefer_const_constructors, avoid_print

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'lat_lng.dart' as latlng;

export 'dart:async' show Completer;
export 'package:google_maps_flutter/google_maps_flutter.dart' hide LatLng;
export 'lat_lng.dart' show LatLng;
import 'package:proj4dart/proj4dart.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

enum GoogleMapStyle {
  standard,
  silver,
  retro,
  dark,
  night,
  aubergine,
}

enum GoogleMarkerColor {
  red,
  orange,
  yellow,
  green,
  cyan,
  azure,
  blue,
  violet,
  magenta,
  rose,
}

Color getRandomColor() {
  Random random = Random();
  return Color.fromARGB(
    255,
    random.nextInt(256),
    random.nextInt(256),
    random.nextInt(256),
  );
}

class FlutterFlowMarker {
  const FlutterFlowMarker(this.markerId, this.location, [this.onTap]);
  final String markerId;
  final latlng.LatLng location;
  final Future Function()? onTap;
}

class FlutterFlowGoogleMap extends StatefulWidget {
  const FlutterFlowGoogleMap({
    required this.controller,
    this.onCameraIdle,
    this.initialLocation,
    this.markers = const [],
    this.markerColor = GoogleMarkerColor.red,
    this.mapType = MapType.satellite,
    this.style = GoogleMapStyle.standard,
    this.initialZoom = 9,
    this.allowInteraction = true,
    this.allowZoom = true,
    this.showZoomControls = true,
    this.showLocation = true,
    this.showCompass = false,
    this.showMapToolbar = false,
    this.showTraffic = false,
    this.centerMapOnMarkerTap = false,
    required this.filter,
    required this.tab,
    super.key,
  });

  final Completer<GoogleMapController> controller;
  final Function(latlng.LatLng)? onCameraIdle;
  final latlng.LatLng? initialLocation;
  final Iterable<FlutterFlowMarker> markers;
  final GoogleMarkerColor markerColor;
  final MapType mapType;
  final GoogleMapStyle style;
  final double initialZoom;
  final bool allowInteraction;
  final bool allowZoom;
  final bool showZoomControls;
  final bool showLocation;
  final bool showCompass;
  final bool showMapToolbar;
  final bool showTraffic;
  final bool centerMapOnMarkerTap;
  final List<String> filter;
  final String tab;
  @override
  State<StatefulWidget> createState() => _FlutterFlowGoogleMapState();
}

class _FlutterFlowGoogleMapState extends State<FlutterFlowGoogleMap> {
  double get initialZoom => max(double.minPositive, widget.initialZoom);
  LatLng get initialPosition =>
      widget.initialLocation?.toGoogleMaps() ?? const LatLng(0.0, 0.0);

  late Completer<GoogleMapController> _controller;
  late LatLng currentMapCenter;
  GoogleMapController? mapController;
  final Set<Polygon> _polygons = <Polygon>{};
  dynamic polygonData;

  void onCameraIdle() => widget.onCameraIdle?.call(currentMapCenter.toLatLng());

  void _showInfo(dynamic info) {
    try {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text("Information"),
            content: SingleChildScrollView(
              child: Table(
                border: TableBorder.all(), // Optional for styling
                columnWidths: const <int, TableColumnWidth>{
                  0: FlexColumnWidth(1.0), // This is for the key column
                  1: FlexColumnWidth(1.0), // This is for the value column
                },
                children: info.entries.map<TableRow>((entry) {
                  return TableRow(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text(entry.key),
                      ),
                      Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text(entry.value.toString()),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          );
        },
      );
    } catch (e) {
      print(e);
    }
  }

  Future<void> fetchData(VoidCallback onDone) async {
    String uri = widget.tab == "Polygon"
        ? 'http://34.72.17.139:8080/geoserver/map_layers_m/wms?service=WMS&version=1.1.0&request=GetMap&layers=map_layers_m%3Aeast_dist_gs&bbox=47.005306243896484%2C25.90535545349121%2C50.24072265625%2C28.50123405456543&width=768&height=616&srs=EPSG%3A4326&styles=&format=geojson'
        : "http://34.72.17.139:8080/geoserver/map_layers_m/wms?service=WMS&version=1.1.0&request=GetMap&layers=map_layers_m%3Aeast_300hex&bbox=353046.0%2C2881169.0%2C424554.0%2C3005812.0&width=440&height=768&srs=EPSG%3A32639&styles=&format=geojson";

    final response = await http.get(Uri.parse(uri));

    if (response.statusCode == 200) {
      dynamic datas = jsonDecode(utf8.decode(response.bodyBytes))['features'];
      setState(() {
        polygonData = datas;
        onDone(); //
      });
    } else {
      throw Exception('Failed to load data');
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
    if (polygonData != null) {
      createPolygons();
    }
  }

  List filterData() {
    if (widget.tab == "Polygon") {
      if (widget.filter.isNotEmpty) {
        String city = widget.filter[0].toLowerCase();
        String engName = widget.filter[1].toLowerCase();
        String arabicName = widget.filter[2].toLowerCase();

        return polygonData.where((feature) {
          final properties = feature['properties'];

          bool matchesCityName = city.isEmpty ||
              (properties['city_name_a'] != null &&
                  properties['city_name_a'].toLowerCase().contains(city));
          bool matchesDistAr = arabicName.isEmpty ||
              (properties['dist_ar'] != null &&
                  properties['dist_ar'].toLowerCase().contains(arabicName));
          bool matchesDistEn = engName.isEmpty ||
              (properties['dist_en'] != null &&
                  properties['dist_en'].toLowerCase().contains(engName));

          return matchesCityName && matchesDistAr && matchesDistEn;
        }).toList();
      } else {
        return polygonData;
      }
    } else {
      return polygonData;
    }
  }

  Color getFillColor(double value) {
    const double desiredOpacity = 0.5;
    if (widget.tab == "Polygon") {
      if (value <= 100) {
        double opacity = (value / 100.0) * desiredOpacity;
        return Color.fromRGBO(96, 247, 97, opacity);
      } else if (value < 500) {
        double opacity = ((value - 100) / 400) * desiredOpacity;
        return Color.lerp(
          Color.fromRGBO(96, 247, 97, desiredOpacity),
          Color.fromRGBO(41, 234, 141, desiredOpacity),
          opacity,
        )!;
      } else if (value < 1000) {
        double opacity = ((value - 500) / 500) * desiredOpacity;
        return Color.lerp(
          Color.fromRGBO(41, 234, 141, desiredOpacity),
          Color.fromRGBO(26, 199, 194, desiredOpacity),
          opacity,
        )!;
      } else if (value < 10000) {
        double opacity = ((value - 1000) / 9000) * desiredOpacity;
        return Color.lerp(
          Color.fromRGBO(26, 199, 194, desiredOpacity),
          Color.fromRGBO(48, 150, 224, desiredOpacity),
          opacity,
        )!;
      } else {
        return Color.fromRGBO(48, 150, 224, desiredOpacity);
      }
    } else {
      if (value <= 1000) {
        double opacity = (value / 1000.0) * desiredOpacity;
        return Color.fromRGBO(96, 247, 97, opacity);
      } else if (value < 2000) {
        double opacity = ((value - 1000) / 1000) * desiredOpacity;
        return Color.lerp(
          Color.fromRGBO(96, 247, 97, desiredOpacity),
          Color.fromRGBO(41, 234, 141, desiredOpacity),
          opacity,
        )!;
      } else if (value < 5000) {
        double opacity = ((value - 2000) / 3000) * desiredOpacity;
        return Color.lerp(
          Color.fromRGBO(41, 234, 141, desiredOpacity),
          Color.fromRGBO(26, 199, 194, desiredOpacity),
          opacity,
        )!;
      } else if (value < 10000) {
        double opacity = ((value - 5000) / 5000) * desiredOpacity;
        return Color.lerp(
          Color.fromRGBO(26, 199, 194, desiredOpacity),
          Color.fromRGBO(48, 150, 224, desiredOpacity),
          opacity,
        )!;
      } else {
        return Color.fromRGBO(48, 150, 224, desiredOpacity);
      }
    }
  }

  Point convertPoint(double x, double y) {
    var pointSrc = Point(x: x, y: y);
    var tuple = ProjectionTuple(
      fromProj: Projection.add(
        'EPSG:32639',
        '+proj=utm +zone=39 +datum=WGS84 +units=m +no_defs',
      ),
      toProj: Projection.get('EPSG:4326')!,
    );
    var pointForward = tuple.forward(pointSrc);
    return Point(y: pointForward.y, x: pointForward.x);
  }

  void createPolygons() {
    var polygons = filterData();
    setState(() {
      _polygons.clear();
      for (final feature in polygons) {
        if (feature['geometry']['type'] == 'Polygon') {
          if (widget.tab == "Polygon") {
            if (feature['properties']['rard'] != null) {
              List<LatLng> polygonCoordinates = [];
              final List<dynamic> coordinates =
                  feature['geometry']['coordinates'].first;
              Color fillColor =
                  getFillColor(feature['properties']['rard'].toDouble());
              for (final List<dynamic> point in coordinates) {
                polygonCoordinates.add(
                  LatLng(point[1].toDouble(), point[0].toDouble()),
                );
              }
              final Polygon polygon = Polygon(
                polygonId: PolygonId('polygon_${_polygons.length}'),
                points: polygonCoordinates,
                strokeWidth: 1,
                strokeColor: Colors.red,
                fillColor: fillColor,
                consumeTapEvents: true,
                onTap: () => _showInfo(feature['properties']),
              );
              setState(() {
                _polygons.add(polygon);
              });
            }
          } else {
            if (feature['properties']['aap'] != null) {
              List<LatLng> polygonCoordinates = [];
              final List<dynamic> coordinates =
                  feature['geometry']['coordinates'].first;
              // Color fillColor = Colors.green;
              Color fillColor =
                  getFillColor(feature['properties']['aap'].toDouble());

              for (final List<dynamic> point in coordinates) {
                var pointForward =
                    convertPoint(point[0].toDouble(), point[1].toDouble());
                polygonCoordinates.add(
                  LatLng(pointForward.y, pointForward.x),
                );
              }
              final Polygon polygon = Polygon(
                polygonId: PolygonId('polygon_${_polygons.length}'),
                points: polygonCoordinates,
                strokeWidth: 1,
                strokeColor: Colors.white,
                fillColor: fillColor,
                consumeTapEvents: true,
                onTap: () => _showInfo(feature['properties']),
              );
              setState(() {
                _polygons.add(polygon);
              });
            }
          }
        }
      }
    });
  }

  void onFilterChanged() {
    createPolygons();
  }

  void onTabChanged() {
    fetchData(() {
      createPolygons();
      if (mapController != null) {
        _onMapCreated(
            mapController!); // Make sure this doesn't cause undesired behavior
      }
    });
  }

  @override
  void initState() {
    super.initState();
    currentMapCenter = initialPosition;
    _controller = widget.controller;
    fetchData(() {
      if (mapController != null) {
        _onMapCreated(mapController!);
      }
    });
  }

  @override
  void didUpdateWidget(FlutterFlowGoogleMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter) {
      onFilterChanged();
    }
    if (oldWidget.tab != widget.tab) {
      onTabChanged(); // Handle the logic for tab change
    }
  }

  @override
  Widget build(BuildContext context) => AbsorbPointer(
        absorbing: !widget.allowInteraction,
        child: GoogleMap(
          onMapCreated: _onMapCreated,
          onCameraIdle: onCameraIdle,
          onCameraMove: (position) => currentMapCenter = position.target,
          initialCameraPosition: CameraPosition(
            target: initialPosition,
            zoom: initialZoom,
          ),
          mapType: MapType.normal,
          zoomGesturesEnabled: widget.allowZoom,
          zoomControlsEnabled: widget.showZoomControls,
          myLocationEnabled: widget.showLocation,
          compassEnabled: widget.showCompass,
          mapToolbarEnabled: widget.showMapToolbar,
          trafficEnabled: widget.showTraffic,
          markers: widget.markers
              .map(
                (m) => Marker(
                  markerId: MarkerId(m.markerId),
                  position: m.location.toGoogleMaps(),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      googleMarkerColorMap[widget.markerColor]!),
                  onTap: () async {
                    await m.onTap?.call();
                    if (widget.centerMapOnMarkerTap) {
                      final controller = await _controller.future;
                      await controller.animateCamera(
                        CameraUpdate.newLatLng(m.location.toGoogleMaps()),
                      );
                      currentMapCenter = m.location.toGoogleMaps();
                      onCameraIdle();
                    }
                  },
                ),
              )
              .toSet(),
          polygons: _polygons,
        ),
      );
}

extension ToGoogleMapsLatLng on latlng.LatLng {
  LatLng toGoogleMaps() => LatLng(latitude, longitude);
}

extension GoogleMapsToLatLng on LatLng {
  latlng.LatLng toLatLng() => latlng.LatLng(latitude, longitude);
}

Map<GoogleMapStyle, String> googleMapStyleStrings = {
  GoogleMapStyle.standard: '[]',
  GoogleMapStyle.silver:
      r'[{"elementType":"geometry","stylers":[{"color":"#f5f5f5"}]},{"elementType":"labels.icon","stylers":[{"visibility":"off"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#f5f5f5"}]},{"featureType":"administrative.land_parcel","elementType":"labels.text.fill","stylers":[{"color":"#bdbdbd"}]},{"featureType":"poi","elementType":"geometry","stylers":[{"color":"#eeeeee"}]},{"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#e5e5e5"}]},{"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},{"featureType":"road","elementType":"geometry","stylers":[{"color":"#ffffff"}]},{"featureType":"road.arterial","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#dadada"}]},{"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},{"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},{"featureType":"transit.line","elementType":"geometry","stylers":[{"color":"#e5e5e5"}]},{"featureType":"transit.station","elementType":"geometry","stylers":[{"color":"#eeeeee"}]},{"featureType":"water","elementType":"geometry","stylers":[{"color":"#c9c9c9"}]},{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]}]',
  GoogleMapStyle.retro:
      r'[{"elementType":"geometry","stylers":[{"color":"#ebe3cd"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#523735"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#f5f1e6"}]},{"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#c9b2a6"}]},{"featureType":"administrative.land_parcel","elementType":"geometry.stroke","stylers":[{"color":"#dcd2be"}]},{"featureType":"administrative.land_parcel","elementType":"labels.text.fill","stylers":[{"color":"#ae9e90"}]},{"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#dfd2ae"}]},{"featureType":"poi","elementType":"geometry","stylers":[{"color":"#dfd2ae"}]},{"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#93817c"}]},{"featureType":"poi.park","elementType":"geometry.fill","stylers":[{"color":"#a5b076"}]},{"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#447530"}]},{"featureType":"road","elementType":"geometry","stylers":[{"color":"#f5f1e6"}]},{"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#fdfcf8"}]},{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#f8c967"}]},{"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#e9bc62"}]},{"featureType":"road.highway.controlled_access","elementType":"geometry","stylers":[{"color":"#e98d58"}]},{"featureType":"road.highway.controlled_access","elementType":"geometry.stroke","stylers":[{"color":"#db8555"}]},{"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#806b63"}]},{"featureType":"transit.line","elementType":"geometry","stylers":[{"color":"#dfd2ae"}]},{"featureType":"transit.line","elementType":"labels.text.fill","stylers":[{"color":"#8f7d77"}]},{"featureType":"transit.line","elementType":"labels.text.stroke","stylers":[{"color":"#ebe3cd"}]},{"featureType":"transit.station","elementType":"geometry","stylers":[{"color":"#dfd2ae"}]},{"featureType":"water","elementType":"geometry.fill","stylers":[{"color":"#b9d3c2"}]},{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#92998d"}]}]',
  GoogleMapStyle.dark:
      r'[{"elementType":"geometry","stylers":[{"color":"#212121"}]},{"elementType":"labels.icon","stylers":[{"visibility":"off"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#212121"}]},{"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#757575"}]},{"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},{"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},{"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#bdbdbd"}]},{"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#181818"}]},{"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},{"featureType":"poi.park","elementType":"labels.text.stroke","stylers":[{"color":"#1b1b1b"}]},{"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#2c2c2c"}]},{"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#8a8a8a"}]},{"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#373737"}]},{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3c3c3c"}]},{"featureType":"road.highway.controlled_access","elementType":"geometry","stylers":[{"color":"#4e4e4e"}]},{"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},{"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"featureType":"water","elementType":"geometry","stylers":[{"color":"#000000"}]},{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#3d3d3d"}]}]',
  GoogleMapStyle.night:
      r'[{"elementType":"geometry","stylers":[{"color":"#242f3e"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#746855"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#242f3e"}]},{"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},{"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},{"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#263c3f"}]},{"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#6b9a76"}]},{"featureType":"road","elementType":"geometry","stylers":[{"color":"#38414e"}]},{"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#212a37"}]},{"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9ca5b3"}]},{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#746855"}]},{"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#1f2835"}]},{"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#f3d19c"}]},{"featureType":"transit","elementType":"geometry","stylers":[{"color":"#2f3948"}]},{"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},{"featureType":"water","elementType":"geometry","stylers":[{"color":"#17263c"}]},{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#515c6d"}]},{"featureType":"water","elementType":"labels.text.stroke","stylers":[{"color":"#17263c"}]}]',
  GoogleMapStyle.aubergine:
      r'[{"elementType":"geometry","stylers":[{"color":"#1d2c4d"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#8ec3b9"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#1a3646"}]},{"featureType":"administrative.country","elementType":"geometry.stroke","stylers":[{"color":"#4b6878"}]},{"featureType":"administrative.land_parcel","elementType":"labels.text.fill","stylers":[{"color":"#64779e"}]},{"featureType":"administrative.province","elementType":"geometry.stroke","stylers":[{"color":"#4b6878"}]},{"featureType":"landscape.man_made","elementType":"geometry.stroke","stylers":[{"color":"#334e87"}]},{"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#023e58"}]},{"featureType":"poi","elementType":"geometry","stylers":[{"color":"#283d6a"}]},{"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#6f9ba5"}]},{"featureType":"poi","elementType":"labels.text.stroke","stylers":[{"color":"#1d2c4d"}]},{"featureType":"poi.park","elementType":"geometry.fill","stylers":[{"color":"#023e58"}]},{"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#3C7680"}]},{"featureType":"road","elementType":"geometry","stylers":[{"color":"#304a7d"}]},{"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#98a5be"}]},{"featureType":"road","elementType":"labels.text.stroke","stylers":[{"color":"#1d2c4d"}]},{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#2c6675"}]},{"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#255763"}]},{"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#b0d5ce"}]},{"featureType":"road.highway","elementType":"labels.text.stroke","stylers":[{"color":"#023e58"}]},{"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#98a5be"}]},{"featureType":"transit","elementType":"labels.text.stroke","stylers":[{"color":"#1d2c4d"}]},{"featureType":"transit.line","elementType":"geometry.fill","stylers":[{"color":"#283d6a"}]},{"featureType":"transit.station","elementType":"geometry","stylers":[{"color":"#3a4762"}]},{"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1626"}]},{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#4e6d70"}]}]',
};

Map<GoogleMarkerColor, double> googleMarkerColorMap = {
  GoogleMarkerColor.red: 0.0,
  GoogleMarkerColor.orange: 30.0,
  GoogleMarkerColor.yellow: 60.0,
  GoogleMarkerColor.green: 120.0,
  GoogleMarkerColor.cyan: 180.0,
  GoogleMarkerColor.azure: 210.0,
  GoogleMarkerColor.blue: 240.0,
  GoogleMarkerColor.violet: 270.0,
  GoogleMarkerColor.magenta: 300.0,
  GoogleMarkerColor.rose: 330.0,
};
