# This file is internal to Flutter and is not for use by external developers.
# It is used to bootstrap the Flutter build system for CocoaPods.

def flutter_root
  # 1. Intentar obtenerlo de la variable de entorno (Muy común en Codemagic/CI)
  return ENV['FLUTTER_ROOT'] if ENV['FLUTTER_ROOT']

  # 2. Intentar buscarlo en Generated.xcconfig (Local)
  # Estamos en ios/Flutter/podhelper.rb, el archivo está en el mismo directorio
  current_dir = File.dirname(__FILE__)
  generated_xcode_build_settings_path = File.join(current_dir, 'Generated.xcconfig')

  if File.exist?(generated_xcode_build_settings_path)
    File.foreach(generated_xcode_build_settings_path) do |line|
      matches = line.match(/\AFLUTTER_ROOT=(.*)\z/)
      return matches[1].strip if matches
    end
  end

  # Si falla todo, lanzar error descriptivo
  raise "Error: FLUTTER_ROOT no encontrada. Asegúrate de que la variable de entorno FLUTTER_ROOT esté definida o ejecuta 'flutter pub get' para generar #{generated_xcode_build_settings_path}"
end

require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper.rb'), flutter_root)
