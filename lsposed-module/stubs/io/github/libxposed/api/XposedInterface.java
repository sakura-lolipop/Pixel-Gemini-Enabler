package io.github.libxposed.api;
import java.lang.reflect.Executable;
public interface XposedInterface {
    HookBuilder hook(Executable origin);
    void log(int priority, String tag, String msg);
    void log(int priority, String tag, String msg, Throwable tr);
    interface Hooker { Object intercept(Chain chain) throws Throwable; }
    interface Chain { Object getArg(int index); Object proceed() throws Throwable; }
    interface HookBuilder { HookHandle intercept(Hooker hooker); }
    interface HookHandle { }
}
