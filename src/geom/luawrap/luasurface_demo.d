/**
 * luasurface_demo.d
 * Demonstrate the wrapped Surface objects.
 *
 * Authors: Rowan G. and Peter J.
 * Version: 2015-02-24
 */

import std.stdio;
import std.conv;
import std.string;
import util.lua;
import geom.luawrap;

void main()
{
    writeln("Begin demonstration of Lua connection to Surface objects.");
    auto L = luaL_newstate();
    luaL_openlibs(L);
    registerVector3(L);
    registerPaths(L);
    registerSurfaces(L);
    string test_code = `
print("Construct from edges")
a = Vector3:new{x=0.0, y=0.0}
b = Vector3:new{x=0.0, y=1.0}
c = Vector3:new{x=1.0, y=0.0}
d = Vector3:new{x=1.0, y=1.0}
surf = CoonsPatch:new{north=Line:new{p0=b, p1=d}, east=Line:new{p0=c, p1=d},
                      south=Line:new{p0=a, p1=c}, west=Line:new{p0=a, p1=b}}
print("CoonsPatch representation: ", surf)
print("surf(0.5,0.5)= ", surf(0.5, 0.5))
--
print("Try construction using corners")
surf2 = CoonsPatch:new{p00=a, p01=b, p11=c, p10=d}
p = surf2:eval(0.5, 0.5)
print("same point p= ", p)
--
print("AO patch")
p00 = Vector3:new{x=0.0, y=0.1, z=3.0}
p10 = Vector3:new{x=1.0, y=0.4, z=3.0}
p11 = Vector3:new{x=1.0, y=1.1, z=3.0}
p01 = Vector3:new{x=0.0, y=1.1, z=3.0}
my_aopatch = AOPatch:new{p00=p00, p10=p10, p11=p11, p01=p01}
p = my_aopatch(0.1, 0.1);
print("my_aopatch(0.1, 0.1)= ", p)
--
print("LuaFnSurface")
function myLuaFunction(r, s)
   -- Simple plane
   return {x=r, y=s, z=0.0}
end
myFnSurface = LuaFnSurface:new{luaFnName="myLuaFunction"}
print("myFnSurface= ", myFnSurface)
print("myFnSurface(0.3, 0.4)= ", myFnSurface(0.3, 0.4))
--
print("SubRangedSurface")
srs = SubRangedSurface:new{underlying_psurface=my_aopatch,
                           r0=0.0, r1=0.5, s0=0.0, s1=0.5}
print("srs(0.2,0.2)=", srs(0.2,0.2))
--
print("ChannelPatch")
cA = Line:new{p0=Vector3:new{x=0.0,y=0.0}, p1=Vector3:new{x=1.0,y=0.0}}
cB = Line:new{p0=Vector3:new{x=0.0,y=0.25}, p1=Vector3:new{x=1.0,y=1.0}}
chanp = ChannelPatch:new{south=cA, north=cB}
print("chanp= ", chanp)
print("chanp(0.5,0.5)= ", chanp(0.5, 0.5))
bpath = chanp:make_bridging_path(0.0)
print("bpath=", bpath)
--
print("SweptPathPatch demo")
cA = Line:new{p0=Vector3:new{x=0.0,y=0.0,z=0.0}, p1=Vector3:new{x=0.0,y=1.0,z=0.0}}
cB = Line:new{p0=Vector3:new{x=1.0,y=0.25,z=0.0}, p1=Vector3:new{x=2.0,y=0.25,z=0.0}}
spp = SweptPathPatch:new{west=cA, south=cB}
print("spp= ", spp)
print("spp(0.5,0.5)= ", spp(0.5, 0.5))
--
print("Utility functions")
print("isSurface(my_aopatch)= ", isSurface(my_aopatch))
print("isSurface(surf2)= ", isSurface(surf2));
print("isSurface(a)= ", isSurface(a));
surf3 = makePatch{north=Line:new{p0=b, p1=d},
                  east=Line:new{p0=c, p1=d},
                  south=Line:new{p0=a, p1=c},
                  west=Line:new{p0=a, p1=b},
                  gridType="ao"}
print("surf3= ", surf3)
print("Done luasurface_demo.")
    `;
    if ( luaL_dostring(L, toStringz(test_code)) != 0 ) {
	writeln("There was a problem interpreting the test code.");
	writeln(to!string(lua_tostring(L, -1)));
    }
    writeln("Done with luageom_demo.");
}

    