import atmos;

unittest
{
    AtmosMixture[9][] superTestMixes;
    foreach(i;0..200)
    {
        import std.random : uniform;
        AtmosMixture[9] testMixSet;
        foreach(n;0..9)
        {
            auto superTestMix=AtmosMixture();
            static foreach(gas; gasesAsArray)
            {
                superTestMix.gases[gas] = uniform(0,2000)*mole;
            }
            superTestMix.temperature = uniform(10,1000000)*kelvin;
            //superTestMix.gases[getGas!"nob"] = 0*mole;
            testMixSet[n]=superTestMix;
        }
        superTestMixes~=testMixSet;
    }
    import std.datetime.systime;
    import core.time : Duration;
    import std.parallelism;
    import std.stdio;
    import std.conv : to;
    auto startTime = Clock.currTime();
    shared ulong totalReactions = 0;
    shared ulong totalShares = 0;
    defaultPoolThreads(defaultPoolThreads/2); //faster for half the cpu usage, hyperthreading dumb
    foreach(n,testMixSet;parallel(superTestMixes,1))
    {
        auto startTimeThisOne = Clock.currTime();
        foreach(i;0..250000)
        {
            foreach(_,superTestMix;testMixSet)
            {
                if(superTestMix.react()==ReactionFlag.REACTING)
                {
                    totalReactions=totalReactions+1;
                }
            }
            testMixSet[0].share(testMixSet[1],2);
            testMixSet[0].share(testMixSet[3],2);
            testMixSet[1].share(testMixSet[2],3);
            testMixSet[1].share(testMixSet[4],3);
            testMixSet[2].share(testMixSet[5],2);
            testMixSet[3].share(testMixSet[4],3);
            testMixSet[3].share(testMixSet[6],3);
            testMixSet[4].share(testMixSet[5],4);
            testMixSet[4].share(testMixSet[7],4);
            testMixSet[5].share(testMixSet[8],3);
            testMixSet[6].share(testMixSet[7],2);
            testMixSet[7].share(testMixSet[8],3);
            testMixSet[8].share(testMixSet[5],2);
            totalShares = totalShares+13;
        }
        Duration totalTimeThisOne=((Clock.currTime())-startTimeThisOne);
        writeln("Done with mix #",n,", took "~totalTimeThisOne.toString~" at total checks/second ",1000000000000000/totalTimeThisOne.total!"nsecs");
    }
    Duration totalTime=((Clock.currTime())-startTime);
    writeln(to!string(totalReactions)~" reactions took a total of "~totalTime.toString~". This is "~to!string((totalReactions*1000)/totalTime.total!"msecs")~" reactions per second, and "~to!string(20000000000/totalTime.total!"msecs")~" reactions checks per second. There were also ",totalShares," shares.");
}