package me.sakura.geminiguard;

import io.github.libxposed.api.XposedInterface;
import io.github.libxposed.api.XposedModule;
import io.github.libxposed.api.XposedModuleInterface.PackageLoadedParam;

/**
 * 拦截 Google PartnerSetup 对 PackageManager.setApplicationEnabledSetting 的调用：
 * 当目标为 com.google.android.apps.bard (Gemini) 且新状态为禁用类时直接吞掉，
 * 其余调用原样放行。作用域 = com.google.android.partnersetup（见 scope.list）。
 */
public class GeminiGuard extends XposedModule {

    private static final String SCOPE = "com.google.android.partnersetup";
    private static final String GEMINI = "com.google.android.apps.bard";

    public GeminiGuard() {
        super();
    }

    @Override
    public void onPackageLoaded(PackageLoadedParam param) {
        if (!SCOPE.equals(param.getPackageName())) {
            return;
        }
        try {
            Class<?> pmc = param.getDefaultClassLoader()
                    .loadClass("android.app.ApplicationPackageManager");
            var m = pmc.getDeclaredMethod("setApplicationEnabledSetting",
                    String.class, int.class, int.class);
            hook(m).intercept((XposedInterface.Chain chain) -> {
                Object pkg = chain.getArg(0);
                if (GEMINI.equals(pkg)) {
                    int state = (Integer) chain.getArg(1);
                    // 0=DEFAULT 1=ENABLED 放行；2=DISABLED 3=DISABLED_USER 4=DISABLED_UNTIL_USED 拦截
                    if (state != 0 && state != 1) {
                        log(5, "GeminiGuard", "blocked setApplicationEnabledSetting(" + pkg + ", " + state + ")");
                        return null;
                    }
                }
                return chain.proceed();
            });
            log(4, "GeminiGuard", "hooked setApplicationEnabledSetting in " + SCOPE);
        } catch (Throwable t) {
            log(6, "GeminiGuard", "hook failed", t);
        }
    }
}
