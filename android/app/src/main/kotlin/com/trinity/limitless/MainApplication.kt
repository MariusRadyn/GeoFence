package com.trinity.limitless

import android.app.Application
import com.google.firebase.appcheck.FirebaseAppCheck
import com.google.firebase.appcheck.playintegrity.PlayIntegrityAppCheckProviderFactory
//import com.google.firebase.appcheck.debug.DebugAppCheckProviderFactory

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()

//        FirebaseAppCheck.getInstance()
//            .installAppCheckProviderFactory(
//                DebugAppCheckProviderFactory.getInstance()
//            )

        FirebaseAppCheck.getInstance()
            .installAppCheckProviderFactory(
                PlayIntegrityAppCheckProviderFactory.getInstance()
        )
    }
}