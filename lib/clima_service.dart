import 'dart:convert';
import 'package:http/http.dart' as http;

class ClimaService {
  static const _baseUrl = 'https://api.open-meteo.com/v1/forecast';
  static const _defaultLat = -2.1761;
  static const _defaultLon = -79.8550;
  static const defaultLocationName = 'Durán, Ecuador';
  static double get defaultLat => _defaultLat;
  static double get defaultLon => _defaultLon;

  static final _weatherCodeNames = <int, String>{
    0: 'Despejado',
    1: 'Mayormente despejado',
    2: 'Parcialmente nublado',
    3: 'Nublado',
    45: 'Niebla',
    48: 'Niebla helada',
    51: 'Llovizna ligera',
    53: 'Llovizna',
    55: 'Llovizna densa',
    61: 'Lluvia ligera',
    63: 'Lluvia moderada',
    65: 'Lluvia fuerte',
    71: 'Nieve ligera',
    73: 'Nieve',
    75: 'Nieve fuerte',
    77: 'Granizo',
    80: 'Chubascos ligeros',
    81: 'Chubascos',
    82: 'Chubascos fuertes',
    85: 'Nevadas ligeras',
    86: 'Nevadas fuertes',
    95: 'Tormenta',
    96: 'Tormenta con granizo',
  };

  static Future<Map<String, dynamic>> getClimaActual({
    double? lat,
    double? lon,
    String? locationName,
  }) async {
    final latitude = lat ?? _defaultLat;
    final longitude = lon ?? _defaultLon;
    final useDefaultCoords = lat == null && lon == null;
    final url = Uri.parse(
      '$_baseUrl?latitude=$latitude&longitude=$longitude'
      '&current=temperature_2m,relative_humidity_2m,weather_code,precipitation,apparent_temperature,wind_speed_10m,wind_direction_10m,surface_pressure'
      '&timezone=auto',
    );

    final res = await http.get(url).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('Error ${res.statusCode}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final current = data['current'] as Map<String, dynamic>?;
    if (current == null) throw Exception('Sin datos de clima');

    final code = current['weather_code'] as int? ?? 0;
    final temp = (current['temperature_2m'] as num?)?.toDouble();
    final humidity = current['relative_humidity_2m'] as int?;
    final precip = (current['precipitation'] as num?)?.toDouble() ?? 0;
    final feelsLike = (current['apparent_temperature'] as num?)?.toDouble();
    final windSpeed = (current['wind_speed_10m'] as num?)?.toDouble();
    final windDir = current['wind_direction_10m'] as int?;
    final pressure = (current['surface_pressure'] as num?)?.toDouble();

    final suelo = _estimarHumedadSuelo(humidity ?? 0, precip);

    final locationLabel = locationName ??
        (useDefaultCoords ? defaultLocationName : 'Tu ubicación');

    final result = <String, dynamic>{
      'temp': temp,
      'feels_like': feelsLike,
      'humidity': humidity,
      'precipitation': precip,
      'weather_code': code,
      'weather_name': _weatherCodeNames[code] ?? 'Desconocido',
      'suelo_nivel': suelo['nivel'],
      'suelo_desc': suelo['desc'],
      'location': locationLabel,
      'wind_speed_kmh': windSpeed,
      'wind_direction': windDir,
      'pressure_hpa': pressure,
    };
    if (!useDefaultCoords) {
      result['lat'] = latitude;
      result['lon'] = longitude;
    }
    return result;
  }

  static Map<String, String> _estimarHumedadSuelo(int airHumidity, double precip) {
    if (precip > 2) {
      return {'nivel': 'Alta', 'desc': 'Precipitación reciente'};
    }
    if (precip > 0.5) {
      return {'nivel': 'Media-alta', 'desc': 'Lluvia reciente'};
    }
    if (airHumidity >= 80) {
      return {'nivel': 'Media', 'desc': 'Aire muy húmedo'};
    }
    if (airHumidity >= 50) {
      return {'nivel': 'Media', 'desc': 'Condiciones moderadas'};
    }
    return {'nivel': 'Baja', 'desc': 'Aire seco'};
  }

  static Future<List<Map<String, dynamic>>> getPronostico4Dias({
    double? lat,
    double? lon,
  }) async {
    final latitude = lat ?? _defaultLat;
    final longitude = lon ?? _defaultLon;
    final url = Uri.parse(
      '$_baseUrl?latitude=$latitude&longitude=$longitude'
      '&daily=temperature_2m_max,temperature_2m_min,weather_code'
      '&forecast_days=4&timezone=auto',
    );

    final res = await http.get(url).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('Error ${res.statusCode}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final daily = data['daily'] as Map<String, dynamic>?;
    if (daily == null) throw Exception('Sin datos de pronóstico');

    final times = (daily['time'] as List).cast<String>();
    final tMax = (daily['temperature_2m_max'] as List).cast<num>();
    final tMin = (daily['temperature_2m_min'] as List).cast<num>();
    final codes = (daily['weather_code'] as List).cast<int>();

    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < times.length && i < 4; i++) {
      final date = DateTime.parse(times[i]);
      final code = codes[i];
      result.add({
        'date': date,
        'temp_max': tMax[i].toDouble(),
        'temp_min': tMin[i].toDouble(),
        'weather_code': code,
        'weather_name': _weatherCodeNames[code] ?? 'Desconocido',
      });
    }
    return result;
  }
}
