class Test {

    static var tests:Int = -1;
    static var fails:Int;

    public static function begin():Void {
        tests = 0;
        fails = 0;
    }

    public static function ce(name:String, check:Dynamic, expect:Dynamic):Void {
        if(tests == -1) throw "Must init Test first";
        tests++;
        if(Std.string(check) != Std.string(expect)){
            trace("--------------");
            trace("Failed \""+name+"\":");
            trace("> Expected:");
            trace(Std.string(expect));
            trace("> Got:");
            trace(Std.string(check));
            trace("--------------");
            fails++;
        }
    }

    static function runFailCE(name:String, check:Array<Dynamic>, expect:Array<Dynamic>):Void {
        trace("--------------");
        trace("Failed \""+name+"\":");
        trace("> Expected:");
        trace(Std.string(expect));
        trace("> Got:");
        trace(Std.string(check));
        trace("--------------");
        fails++;
    }

    // Check a set of elements against another, independent of order
    public static function ceSet(name:String, check:Array<Dynamic>, expect:Array<Dynamic>):Void {
        if(tests == -1) throw "Must init Test first";
        tests++;

        if(check == null && expect != null){
            return runFailCE(name, check, expect);
        }
        if(expect == null && check != null){
            return runFailCE(name, check, expect);
        }

        if(check.length != expect.length){
            return runFailCE(name, check, expect);
        }

        var checkSet = new Array<String>();
        for(obj in check){
            var str = Std.string(obj);
            checkSet.push(str);
        }

        for(obj in expect){
            var str = Std.string(obj);
            var idx = checkSet.indexOf(str);
            if(idx == -1){
                return runFailCE(name, check, expect);
            }
            checkSet.splice(idx, 1);
        }
    }

    public static function ceRef(name:String, val:Dynamic, val2:Dynamic):Void {
        if(tests == -1) throw "Must init Test first";
        tests++;
        if(val != val2){
            trace("--------------");
            trace("Failed \""+name+"\":");
            trace("> Expected Object References don't match.");
            trace("--------------");
            fails++;
        }
    }

    public static function end(successMsg:Bool = false):Void {
        if(fails == 0){
            if(successMsg){
                trace("Passed all "+tests+" tests");
            }
            Sys.exit(0);
        }
        trace("Failed "+fails+"/"+tests);
        Sys.exit(-1);
    }
}
