gas = 'N'
number_of_bins = 8
ionised_bin = true

bins = {}

bins[0] = {
    name = 'NI-1',
    bin_level = 1,
    M = 0.0140067,
	lower_level = 1,
	upper_level = 1,
	group_energy = 0.0,
	group_degeneracy = 4
}

bins[1] = {
    name = 'NI-2',
    bin_level = 2,
    M = 0.0140067,
	lower_level = 2,
	upper_level = 2,
	group_energy = 2.384,
	group_degeneracy = 10
}

bins[2] = {
    name = 'NI-3',
    bin_level = 3,
    M = 0.0140067,
	lower_level = 3,
	upper_level = 3,
	group_energy = 3.576,
	group_degeneracy = 6
}

bins[3] = {
    name = 'NI-4',
    bin_level = 4,
    M = 0.0140067,
	lower_level = 4,
	upper_level = 6,
	group_energy = 10.641,
	group_degeneracy = 30
}

bins[4] = {
    name = 'NI-5',
    bin_level = 5,
    M = 0.0140067,
	lower_level = 7,
	upper_level = 13,
	group_energy = 11.95084375,
	group_degeneracy = 4
}

bins[5] = {
    name = 'NI-6',
    bin_level = 6,
    M = 0.0140067,
	lower_level = 14,
	upper_level = 21,
	group_energy = 12.9847636364,
	group_degeneracy = 110
}

bins[6] = {
    name = 'NI-7',
    bin_level = 7,
    M = 0.0140067,
	lower_level = 22,
	upper_level = 27,
	group_energy = 13.34203125,
	group_degeneracy = 64
}

bins[7] = {
    name = 'NI-8',
    bin_level = 8,
    M = 0.0140067,
	lower_level = 28,
	upper_level = 46,
	group_energy = 13.9876399132,
	group_degeneracy = 922
}

bins[8] = {
    name = 'NII',
    bin_level = 9,
    M = 0.0140067,
	lower_level = 0,
	upper_level = 0,
	group_energy = 14.53413,
	group_degeneracy = 0
}


reactions = {}

reactions[0] = {
    lower_bin = 1.0,
    upper_bin = 2.0,
    A = 5.77000000001e-08,
    n = -0.160268851,
    E = 40116.89956,
    G1 = 1.94082774097e-11,
    G2 = 2.01321901337e-11,
    G3 = 5.697972454e-11,
    G4 = -5.5330555975,
    G5 = 4.15078223517e-12,
}

reactions[1] = {
    lower_bin = 1.0,
    upper_bin = 3.0,
    A = 3.11000000002e-08,
    n = -0.204736499001,
    E = 44700.53167,
    G1 = 2.78647663472e-11,
    G2 = 3.06839281692e-11,
    G3 = 8.30501027113e-11,
    G4 = -8.29958339625,
    G5 = 6.20928777413e-12,
}

reactions[2] = {
    lower_bin = 1.0,
    upper_bin = 4.0,
    A = 7.17631184914e-07,
    n = -0.30955666274,
    E = 116964.370687,
    G1 = 0.135088432366,
    G2 = 0.568879848732,
    G3 = 1.39802928656,
    G4 = -25.6567358009,
    G5 = 0.0799200891069,
}

reactions[3] = {
    lower_bin = 1.0,
    upper_bin = 5.0,
    A = 2.12118912984e-09,
    n = 0.232942040496,
    E = 136741.366043,
    G1 = 0.0265439923531,
    G2 = 0.564645041088,
    G3 = 1.17946625399,
    G4 = -28.5729417856,
    G5 = 0.0700179146922,
}

reactions[4] = {
    lower_bin = 1.0,
    upper_bin = 6.0,
    A = 7.19467945011e-10,
    n = 0.290250657674,
    E = 153391.258852,
    G1 = -0.0184284752672,
    G2 = 0.560915694278,
    G3 = 1.08658557965,
    G4 = -30.9190651589,
    G5 = 0.0656925104744,
}

reactions[5] = {
    lower_bin = 1.0,
    upper_bin = 7.0,
    A = 3.07111935412e-09,
    n = 0.0816496452093,
    E = 154346.797559,
    G1 = 0.0313531575816,
    G2 = 0.56502379423,
    G3 = 1.18937477342,
    G4 = -31.807466479,
    G5 = 0.0704781971725,
}

reactions[6] = {
    lower_bin = 1.0,
    upper_bin = 8.0,
    A = 3.4342001344e-09,
    n = 0.208977469243,
    E = 160143.030601,
    G1 = -0.232551390177,
    G2 = 0.538588738987,
    G3 = 0.639014133579,
    G4 = -32.9867573224,
    G5 = 0.0445829381639,
}

reactions[7] = {
    lower_bin = 1.0,
    upper_bin = 0.0,
    A = 5.69000000008e-12,
    n = 0.720999999999,
    E = 336562.225987,
    G1 = 0.156843520086,
    G2 = 50.6401996364,
    G3 = -1.47344432218,
    G4 = -16.8739086675,
    G5 = 0.000126919425498,
}

reactions[8] = {
    lower_bin = 2.0,
    upper_bin = 3.0,
    A = 1.45749999998e-05,
    n = -0.536399906998,
    E = 54343.2050173,
    G1 = 8.58064011347e-12,
    G2 = 8.71174945181e-12,
    G3 = 2.50596034714e-11,
    G4 = -2.76652779875,
    G5 = 1.80829196488e-12,
}

reactions[9] = {
    lower_bin = 2.0,
    upper_bin = 4.0,
    A = 9.72902826275e-08,
    n = -0.126878451307,
    E = 122325.626557,
    G1 = 0.135088432351,
    G2 = 0.568879848713,
    G3 = 1.39802928651,
    G4 = -20.1236802034,
    G5 = 0.0799200891032,
}

reactions[10] = {
    lower_bin = 2.0,
    upper_bin = 5.0,
    A = 2.71559646415e-07,
    n = -0.131493630502,
    E = 141601.648341,
    G1 = 0.0265439923605,
    G2 = 0.564645041092,
    G3 = 1.17946625401,
    G4 = -23.0398861882,
    G5 = 0.0700179146932,
}

reactions[11] = {
    lower_bin = 2.0,
    upper_bin = 6.0,
    A = 6.32229791318e-08,
    n = -0.0191328028526,
    E = 155376.067464,
    G1 = -0.0184284752432,
    G2 = 0.560915694302,
    G3 = 1.08658557972,
    G4 = -25.3860095615,
    G5 = 0.0656925104793,
}

reactions[12] = {
    lower_bin = 2.0,
    upper_bin = 7.0,
    A = 5.98501042939e-09,
    n = 0.109221883265,
    E = 154439.433389,
    G1 = 0.0313531575905,
    G2 = 0.565023794237,
    G3 = 1.18937477344,
    G4 = -26.2744108816,
    G5 = 0.070478197174,
}

reactions[13] = {
    lower_bin = 2.0,
    upper_bin = 8.0,
    A = 8.74798148514e-09,
    n = 0.227614068496,
    E = 160114.923785,
    G1 = -0.232551390152,
    G2 = 0.538588739022,
    G3 = 0.63901413366,
    G4 = -27.453701725,
    G5 = 0.0445829381704,
}

reactions[14] = {
    lower_bin = 2.0,
    upper_bin = 0.0,
    A = 1.80250000006e-10,
    n = 0.548699999997,
    E = 308762.225987,
    G1 = 0.156843520089,
    G2 = 50.6401996364,
    G3 = -1.47344432217,
    G4 = -16.8739086675,
    G5 = 0.00012691942613,
}

reactions[15] = {
    lower_bin = 3.0,
    upper_bin = 4.0,
    A = 5.2862261943e-08,
    n = -0.105175230748,
    E = 122480.634458,
    G1 = 0.135088432354,
    G2 = 0.568879848717,
    G3 = 1.39802928652,
    G4 = -17.3571524047,
    G5 = 0.0799200891039,
}

reactions[16] = {
    lower_bin = 3.0,
    upper_bin = 5.0,
    A = 6.2571949613e-08,
    n = -0.0382190841454,
    E = 139384.495241,
    G1 = 0.0265439923148,
    G2 = 0.564645041037,
    G3 = 1.17946625387,
    G4 = -20.2733583893,
    G5 = 0.0700179146822,
}

reactions[17] = {
    lower_bin = 3.0,
    upper_bin = 6.0,
    A = 2.84664326321e-08,
    n = 0.0289764667185,
    E = 155410.308349,
    G1 = -0.0184284752395,
    G2 = 0.560915694309,
    G3 = 1.08658557973,
    G4 = -22.6194817628,
    G5 = 0.0656925104805,
}

reactions[18] = {
    lower_bin = 3.0,
    upper_bin = 7.0,
    A = 3.11257701633e-09,
    n = 0.126784650546,
    E = 154518.574713,
    G1 = 0.0313531576229,
    G2 = 0.565023794277,
    G3 = 1.18937477354,
    G4 = -23.5078830829,
    G5 = 0.0704781971819,
}

reactions[19] = {
    lower_bin = 3.0,
    upper_bin = 8.0,
    A = 5.46906114964e-09,
    n = 0.236683422585,
    E = 160100.21804,
    G1 = -0.232551390192,
    G2 = 0.538588738976,
    G3 = 0.639014133539,
    G4 = -24.6871739262,
    G5 = 0.0445829381613,
}

reactions[20] = {
    lower_bin = 3.0,
    upper_bin = 0.0,
    A = 2.43000000012e-11,
    n = 0.669099999995,
    E = 295262.225987,
    G1 = 0.156843520089,
    G2 = 50.6401996364,
    G3 = -1.47344432217,
    G4 = -16.8739086675,
    G5 = 0.00012691942621,
}

reactions[21] = {
    lower_bin = 4.0,
    upper_bin = 5.0,
    A = 0.000320587738495,
    n = -0.538018371282,
    E = 139271.463929,
    G1 = -0.108544440017,
    G2 = -0.00423480765129,
    G3 = -0.218563032581,
    G4 = -2.91620598467,
    G5 = -0.00990217441618,
}

reactions[22] = {
    lower_bin = 4.0,
    upper_bin = 6.0,
    A = 0.000590717637268,
    n = -0.628669072906,
    E = 153660.72386,
    G1 = -0.153516907575,
    G2 = -0.00796415439041,
    G3 = -0.311443706735,
    G4 = -5.26232935806,
    G5 = -0.0142275786198,
}

reactions[23] = {
    lower_bin = 4.0,
    upper_bin = 7.0,
    A = 0.000210618039065,
    n = -0.62201709772,
    E = 157413.016657,
    G1 = -0.103735274789,
    G2 = -0.00385605451011,
    G3 = -0.208654513153,
    G4 = -6.15073067804,
    G5 = -0.00944189193606,
}

reactions[24] = {
    lower_bin = 4.0,
    upper_bin = 8.0,
    A = 0.000292717587038,
    n = -0.55345696875,
    E = 163142.316006,
    G1 = -0.36763982252,
    G2 = -0.0302911097122,
    G3 = -0.759015152901,
    G4 = -7.33002152151,
    G5 = -0.035337150937,
}

reactions[25] = {
    lower_bin = 4.0,
    upper_bin = 0.0,
    A = 1.25393365755e-06,
    n = -0.0896540362081,
    E = 215149.877214,
    G1 = 0.291931952413,
    G2 = 51.2090794851,
    G3 = -0.0754150357407,
    G4 = -17.8338136745,
    G5 = 0.0800470085236,
}

reactions[26] = {
    lower_bin = 5.0,
    upper_bin = 6.0,
    A = 0.00854303162253,
    n = -0.673394319921,
    E = 153712.386994,
    G1 = -0.0449724675653,
    G2 = -0.0037293467448,
    G3 = -0.0928806741726,
    G4 = -2.34612337338,
    G5 = -0.00432540420486,
}

reactions[27] = {
    lower_bin = 5.0,
    upper_bin = 7.0,
    A = 0.00105680480722,
    n = -0.643457298873,
    E = 157828.771525,
    G1 = 0.00480916523413,
    G2 = 0.000378753150937,
    G3 = 0.00990851944966,
    G4 = -3.23452469338,
    G5 = 0.000460282481977,
}

reactions[28] = {
    lower_bin = 5.0,
    upper_bin = 8.0,
    A = 0.00168994634043,
    n = -0.579528849806,
    E = 163162.393043,
    G1 = -0.259095382506,
    G2 = -0.0260563020657,
    G3 = -0.540452120331,
    G4 = -4.41381553683,
    G5 = -0.0254349765217,
}

reactions[29] = {
    lower_bin = 5.0,
    upper_bin = 0.0,
    A = 5.6032598083e-05,
    n = -0.298188212296,
    E = 199855.388436,
    G1 = 0.18338751243,
    G2 = 51.2048446775,
    G3 = -0.293978068223,
    G4 = -17.7099868183,
    G5 = 0.0701448341145,
}

reactions[30] = {
    lower_bin = 6.0,
    upper_bin = 7.0,
    A = 0.092307083444,
    n = -0.691632173764,
    E = 157576.578142,
    G1 = 0.0497816328027,
    G2 = 0.00410809989947,
    G3 = 0.102789193632,
    G4 = -0.888401320012,
    G5 = 0.00478568668759,
}

reactions[31] = {
    lower_bin = 6.0,
    upper_bin = 8.0,
    A = 0.0233331893945,
    n = -0.631015783206,
    E = 163223.190513,
    G1 = -0.214122914942,
    G2 = -0.0223269553209,
    G3 = -0.447571446161,
    G4 = -2.06769216345,
    G5 = -0.0211095723169,
}

reactions[32] = {
    lower_bin = 6.0,
    upper_bin = 0.0,
    A = 0.00376426739979,
    n = -0.558752683335,
    E = 190730.846943,
    G1 = 0.138415044847,
    G2 = 51.2011153307,
    G3 = -0.386858742451,
    G4 = -17.6564725178,
    G5 = 0.065819429905,
}

reactions[33] = {
    lower_bin = 7.0,
    upper_bin = 8.0,
    A = 0.0793731962565,
    n = -0.650412919092,
    E = 162430.217776,
    G1 = -0.263904547742,
    G2 = -0.0264350552173,
    G3 = -0.550360639785,
    G4 = -1.17929084344,
    G5 = -0.0258952590039,
}

reactions[34] = {
    lower_bin = 7.0,
    upper_bin = 0.0,
    A = 0.00324669484369,
    n = -0.548543352869,
    E = 184904.773999,
    G1 = 0.188196677654,
    G2 = 51.2052234306,
    G3 = -0.284069548804,
    G4 = -17.7156869379,
    G5 = 0.0706051165942,
}

reactions[35] = {
    lower_bin = 8.0,
    upper_bin = 0.0,
    A = 7.05826900553,
    n = -0.892010156661,
    E = 177222.829128,
    G1 = -0.0757078701235,
    G2 = 51.1787883754,
    G3 = -0.834430188696,
    G4 = -17.3965765111,
    G5 = 0.044709857582,
}
