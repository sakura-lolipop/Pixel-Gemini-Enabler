package io.github.libxposed.api;
import java.lang.reflect.Executable;
public class XposedInterfaceWrapper implements XposedInterface {
    public final void attachFramework(XposedInterface base, Runnable detachImpl) { }
    public final int getApiVersion() { return 0; }
    public final HookBuilder hook(Executable origin) { throw new UnsupportedOperationException(); }
    public final void log(int priority, String tag, String msg) { }
    public final void log(int priority, String tag, String msg, Throwable tr) { }
}
