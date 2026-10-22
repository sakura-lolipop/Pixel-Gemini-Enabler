package io.github.libxposed.api;
public interface XposedModuleInterface {
    default void onPackageLoaded(PackageLoadedParam param) { }
    interface PackageLoadedParam {
        String getPackageName();
        ClassLoader getDefaultClassLoader();
        boolean isFirstPackage();
    }
}
