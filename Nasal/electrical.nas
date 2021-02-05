#//Followme EV electrical system by Sidi Liang
#//Contact: sidi.liang@gmail.com

#//Notes: switch should be changed to a (very very) large resistant

var kWh2kWs = func(kWh){
    return kWh * 3600;
}
var kWs2kWh = func(kWs){
    return kWs / 3600;
}

var Series = {
    #//Class for any series connection
    new: func() {
        return { parents:[Series] };
    },
    units: [],
    addUnit: func(unit){
        append(me.units, unit);
    },
    isSwitch: func(){
        return 0;
    },

    totalResistance: func(){
        var total = 0;
        foreach(elem; me.units){
            total += elem.resistance;
        }
        return total;
    },

    totalActivePower: func(){
        var total = 0;
        foreach(elem; me.units){
            total += elem.activePower;
            total += elem.activePower_kW * 1000;
        }
        return total;
    },

    totalPower: func(){
        var total = 0;
        foreach(elem; me.units){
            total += elem.power();
        }
        return total;
    },


    voltage: 0, #//Volt
    current: func(){
        foreach(elem; me.units){
            if(elem.isSwitch()){
                if(!elem.isConnected()){
                    return 0;
                }
            }
        }
        #//Calculated by solving the equation UI = I^2*R + Power output
        var R = me.totalResistance();
        var U = me.voltage;
        var Pout=me.totalActivePower();
        if(U == 0) return 0;#//No voltage, no current.

        #//Trying to solve the floating point error at the next line
        # print("U ",U," R ",R," Pout ",Pout);
        # print("delta^2 ",U*U - 4*R*Pout);
        var delta = math.sqrt(U*U - 4*R*Pout);

        #//used to be minus, but adding it seems to be correct
        return (U+delta)/(2*R); #//Ampere
    },

	calculateTotalCounterElectromotiveForce: func(){
		#//Total counterElectromotiveForce, calculated from UI = I^R + Power output
		return me.voltage - me.current() * me.totalResistance();
	},


    calculateSeriesVoltage: func(){
        cElectromotiveForce = me.calculateTotalCounterElectromotiveForce();
        #//me.voltage = me.voltage - cElectromotiveForce; #//Voltage with counterElectromotiveForce in consideration
        totalTmp = 0;
        foreach(elem; me.units){
            totalTmp += elem.current * elem.current * elem.resistance + elem.activePower + elem.activePower_kW * 1000;
        }
        foreach(elem; me.units){
            if(elem.isSwitch()){
                if(!elem.isConnected()){
                    me.voltage = 0;
                }
            }
            var factor = (elem.current * elem.current * elem.resistance + elem.activePower + elem.activePower_kW * 1000)/totalTmp;
            elem.voltage = me.voltage * factor;
        }
    },

    calculateSeriesCurrent: func(){
        foreach(elem; me.units){
            elem.current = me.current();
        }
    },
};

var Circuit = {
    #//Class for any circuit
    #//Currently must be initalized with a source
    #//Currently only support one current source in a circuit
    new: func(cSource) {
        var new_circuit = { parents:[Circuit] };
        new_circuit.addNewSeriesWithUnitToParallel(cSource);
        return new_circuit;
    },


    parallelConnection: [],

    newSeriesWithUnits: func(addedUnits...){
        var newSeries = Series.new();
        foreach(elem; addedUnits){
            newSeries.addUnit(elem);
        }
        return newSeries;
    },


    addUnitToSeries: func(seriesNum, unit){
        me.parallelConnection[seriesNum].addUnit(unit);
    },

    addParallel: func(units){
      append(me.parallelConnection, units);
    },

    addNewSeriesWithUnitToParallel: func(units){
        var new_series = me.newSeriesWithUnits(units);
        me.addParallel(new_series);
    },


    current: 0, #//Ampere
    voltage: func(){ #//Terminal voltage
        var v = me.parallelConnection[0].units[0].electromotiveForce - me.calculateTotalParallelCurrent()*me.parallelConnection[0].units[0].resistance;
        foreach(elem; me.parallelConnection){
            if(elem.isSwitch()){
               continue;
            }
			      v -= elem.calculateTotalCounterElectromotiveForce();#//All counterElectromotiveForce is substracted
        }

        #if(me.calculateTotalParallelCurrent()){
        #   v = me.parallelConnection[0].units[0].electromotiveForce - me.calculateTotalParallelCurrent()*me.parallelConnection[0].units[0].resistance;
        #}
        #foreach(elem; me.parallelConnection){
        #    if(elem.voltage != v){
        #        v = elem.voltage;
        #        break;
        #    }
        #}
        return v
    }, #//Volt

    calculateParallelVoltage: func(){
        var setVoltage = me.voltage();
        #//var totalCounterElecMotiveForce = 0;
        foreach(elem; me.parallelConnection){
            if(elem.isSwitch()){
                if(!elem.isConnected()){
                    setVoltage = 0;
                }
            }
            elem.voltage = setVoltage;
        }
    }, #//Volt

    calculateSeriesVoltage: func(){
        foreach(elem; me.parallelConnection){
            elem.calculateSeriesVoltage();
        }
    }, #//Volt

    calculateTotalParallelCurrent: func(){
        var total = 0;
        foreach(elem; me.parallelConnection){
            if(elem.isSwitch()){
                if(!elem.isConnected()){
                    me.current = 0;
                    return 0;
                }
            }
            total += elem.current();
        }
        me.current = total;
        return total;
    }, #//Ampere

    calculateTotalPower: func(){
      var total = 0;
      foreach(elem; me.parallelConnection){
          total += elem.totalPower();
      }
      return total;
    },

    updateInterval: 1, #//Seconds between each update

    debugMode: 0,

    loopCount: 0,

    update: func(){
        if(me.debugMode) print("Loop Count: "~me.loopCount);

        me.calculateParallelVoltage();
        if(me.debugMode == 2) print("Parallel Voltage Calculated");

        me.calculateSeriesVoltage();
        if(me.debugMode == 2) print("Series Voltage Calculated");

        foreach(elem; me.parallelConnection){
            elem.calculateSeriesCurrent();
        }
        if(me.debugMode == 2) print("Series Current Calculated");

        me.calculateTotalParallelCurrent();
        if(me.debugMode == 2) print("Parallel Current Calculated");

        foreach(elem; me.parallelConnection){
            foreach(unit; elem.units){
                if(unit.isCurrentSource()) unit.currentSourceUpdate(me.calculateTotalPower(), me.updateInterval); #//Update the current source. Pass in negetive power in case of charging
            }
        }
        if(me.debugMode == 2) print("Power Calculated");
        if(me.debugMode) print("Power: "~me.calculateTotalPower());

        props.getNode("/systems/electrical/e-tron/battery-kWh", 1).setValue(me.parallelConnection[0].units[0].getRemainingInkWh());
        props.getNode("/systems/electrical/e-tron/battery-remaining-percent", 1).setValue(me.parallelConnection[0].units[0].getRemainingPercentage());
        props.getNode("/systems/electrical/e-tron/battery-remaining-percent-float", 1).setValue(me.parallelConnection[0].units[0].getRemainingPercentageFloat());

        if(me.debugMode) print("current: "~me.current);
        if(me.debugMode) print("voltage: "~me.voltage());
        if(me.debugMode) print("Main Battery Remaining: "~me.parallelConnection[0].units[0].remaining);
        #//if(me.debugMode)
        #//print("Secondery Battery Remaining: "~me.parallelConnection[0].units[0].remaining);

        me.loopCount += 1;
    },


};

var Appliance = {
    #//Class for any electrical appliance
    new: func() {
        return { parents:[Appliance] };
    },

    isCurrentSource: func(){
        return 0;
    },

    ratedPower: 0, #//rate power , Watt, 0 if isResistor

    isSwitch: func(){
        return 0;
    },

    resistance: 0, #//electric resistance, Ωμέγα
    resistivity: 0,#//Ω·m
    voltage: 0, #//electric voltage, Volt
    current: 0, #//electric current, Ampere
    activePower: 0, #//Output Power, Watt
    activePower_kW: 0, #//Output Power, kWatt, independence of activePower
    heatingPower: func(){
        return me.current * me.current * me.resistance;
    },#//heating Power
    power: func(){
      return me.activePower + me.activePower_kW*1000 + me.heatingPower();
    },
    counterElectromotiveForce: func(){
        return (me.activePower + me.activePower_kW*1000)/me.current; #//Counter Electromotive Force calculated by output power divided by current
    },

    isResistor: 0,

    applianceName: "Appliance",
    applianceDescription: "This is a electric appliance",

    setName: func(text){
        me.applianceName = text;
    },
    setDescription: func(text){
        me.applianceDescription = text;
    },
    setResistance: func(r){
        me.resistance = r;
    },
};

var CurrentSource = {
    #//Class for any current source
    #//eR: Internal resistance of the source, eF: Electromotive force of the source, eC: Electrical capacity of the source, name: Name of the source.
    new: func(eR, eF, eC, name = "CurrentSource") {
        var newCS = { parents:[CurrentSource, Appliance.new()], resistance: eR, ratedElectromotiveForce:eF, electromotiveForce:eF, electricalCapacity:eC, applianceName: name };
        newCS.resetRemainingToFull();
        return newCS;
    },

    isCurrentSource: func(){
        return 1;
    },

    direction: 1, #//1 means it is connected in the current direction, -1 means the opposite
    ratedElectromotiveForce: 0, #//Volt
    electromotiveForce: 0, #//Volt
    electricalCapacity: 0, #//kWs
    remaining: 0, #//kWs


    currentSourceUpdate: func(power, interval){
        me.remaining -= power * 0.001 * interval; #//Pass in negetive power for charging
        if(me.remaining <= 0){
            me.electromotiveForce = 0;
        }else{
            me.electromotiveForce = me.ratedElectromotiveForce;
        }
    },

    #//Usage: followme.circuit_1.parallelConnection[0].units[0].resetRemainingToFull();
    resetRemainingToFull: func(){
        me.remaining = me.electricalCapacity;
    },
    resetRemainingToZero: func(){
        me.remaining = 0;
    },
    getRemainingPercentage: func(){
        return sprintf("%.0f", 100 * me.remaining / me.electricalCapacity)~"%";
    },
    getRemainingPercentageFloat: func(){
        return sprintf("%.0f", 100 * me.remaining / me.electricalCapacity);
    },
    getRemainingInkWh: func(){
        return me.remaining/3600;
    },
    addToBattery: func(num){
        me.remaining += num;
    },

};

var Switch = {
    #//Class for any switches
    #//Type 0 for appliance switch. type 1 for series switch
    #//switchToggle: Return 1 if connected, return 0 if disconnected
    new: func(type, name = "Switch") {
        if(type == 0){
            var newCS = { parents:[Switch, Appliance.new()], applianceName: name };
            return newCS;
        }else if(type == 1){
            var newCS = { parents:[Switch, Series.new()]};
            return newCS;
        }
    },
    isSwitch: func(){
        return 1;
    },

    switchState: 1, #//0 for disconnect, 1 for connect

    isConnected: func(){
        if(me.switchState){
            return 1;
        }else if(!me.switchState){
            return 0;
        }
    },

    switchConnect: func(){
        me.switchState = 1;
        return 1;
    },
    switchDisconnect: func(){
        me.switchState = 0;
        return 0;
    },
    switchToggle: func(){
        if(me.isConnected()){
            return me.switchDisconnect();
        }else if(!me.isConnected()){
            return me.switchConnect();
        }
    },

};

var Cable = {
    #//Class for any copper electrical cable
    new: func(l = 0, s = 0.008) {
        var newCable = { parents:[Cable, Appliance.new()], resistivity: 1.75 * 0.00000001, length: l, crossSection: s};
        print("Created Cable with resistance of " ~ newCable.setResistance());
        return newCable;
    },
    length: 0,#//Meter
    crossSection: 0,#//Meter^2
    setResistance: func(){
        me.resistance = (me.resistivity * me.length) / me.crossSection;
        return me.resistance;
    }
};

var cSource = CurrentSource.new(0.0136, 760, kWh2kWs(80), "Battery");#//Battery for engine, 80kWh, 760V
var circuit_1 = Circuit.new(cSource);#//Engine circuit

var cSource_small = CurrentSource.new(0.0136, 12, kWh2kWs(0.72), "Battery");#//Battery for other systems, 60Ah, 12V
cSource_small.resetRemainingToZero();
#circuit_1.addNewSeriesWithUnitToParallel(cSource_small);


#circuit_1.addUnitToSeries(0, Cable.new(10, 0.008));
#circuit_1.addUnitToSeries(0, Switch.new(0));
#circuit_1.addParallel(Switch.new(1));



var electricTimer1 = maketimer(circuit_1.updateInterval, func circuit_1.update());
electricTimer1.simulatedTime = 1;

var L = setlistener("/sim/signals/fdm-initialized", func{
    electricTimer1.start();
});
