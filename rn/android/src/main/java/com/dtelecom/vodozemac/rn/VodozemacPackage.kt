// Package entry point that React Native's autolink CLI discovers. RN
// uses this class to register the TurboModule with the host app.

package com.dtelecom.vodozemac.rn

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider

class VodozemacPackage : BaseReactPackage() {

    override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? {
        return if (name == VodozemacModule.NAME) VodozemacModule(reactContext) else null
    }

    override fun getReactModuleInfoProvider(): ReactModuleInfoProvider {
        return ReactModuleInfoProvider {
            mapOf(
                VodozemacModule.NAME to ReactModuleInfo(
                    /* name = */ VodozemacModule.NAME,
                    /* className = */ VodozemacModule::class.java.name,
                    /* canOverrideExistingModule = */ false,
                    /* needsEagerInit = */ false,
                    /* isCxxModule = */ false,
                    /* isTurboModule = */ true,
                ),
            )
        }
    }
}
