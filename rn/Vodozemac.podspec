require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "Vodozemac"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = { package["author"].split("<")[0].strip => package["author"].match(/<(.+)>/)[1] }
  s.platforms    = { :ios => "15.1" }
  s.source       = { :git => "https://github.com/dTelecom/vodozemac-wasm.git", :tag => "#{s.version}" }

  # Native sources for the TurboModule. No .h files — the .mm declares
  # its own @interface inline so the pod's umbrella header stays empty,
  # which prevents Swift from auto-parsing C++ deps that come in via
  # `<RTNVodozemacSpec/RTNVodozemacSpec.h>`.
  s.source_files = "ios/**/*.{m,mm,swift}"
  s.requires_arc = true

  # UniFFI's xcframework (vendored as a binary dep). Contains the static
  # libs + headers + module map for VodozemacFFIFFI (the C interop layer).
  s.vendored_frameworks = "ios/VodozemacFFI.xcframework"

  # Defining the module enables `import Vodozemac` from Swift consumers
  # (and Swift inside this same pod). Without it, Vodozemac.swift can't
  # find VodozemacImpl when Vodozemac.mm's `Vodozemac-Swift.h` looks for it.
  s.pod_target_xcconfig = {
    "DEFINES_MODULE" => "YES",
  }

  # Wire up RN's React + ReactCommon dependencies, ReactCodegen, and
  # define `RCT_NEW_ARCH_ENABLED` for the new architecture build. This
  # helper exists in RN 0.74+ — older RN releases don't have it.
  install_modules_dependencies(s)
end
