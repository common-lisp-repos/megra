SynthDef(\reverb_16ch, {
	var in1, in2, in3, in4, in5, in6, in7, in8, in9, in10, in11, in12, in13, in14, in15, in16;
	var out1, out2, out3, out4, out5, out6, out7, out8, out9, out10, out11, out12, out13, out14, out15, out16;
	# in1, in2, in3, in4, in5, in6, in7, in8, in9, in10, in11, in12, in13, in14, in15, in16 = In.ar(16, 16);

	out1 = PartConv.ar(in1, 2048, 1, 1.0);
	out2 = PartConv.ar(in2, 2048, 1, 1.0);
	out3 = PartConv.ar(in3, 2048, 1, 1.0);
	out4 = PartConv.ar(in4, 2048, 1, 1.0);
	out5 = PartConv.ar(in5, 2048, 1, 1.0);
	out6 = PartConv.ar(in6, 2048, 1, 1.0);
	out7 = PartConv.ar(in7, 2048, 1, 1.0);
	out8 = PartConv.ar(in8, 2048, 1, 1.0);
	out9 = PartConv.ar(in9, 2048, 1, 1.0);
	out10 = PartConv.ar(in10, 2048, 1, 1.0);
	out11 = PartConv.ar(in11, 2048, 1, 1.0);
	out12 = PartConv.ar(in12, 2048, 1, 1.0);
	out13 = PartConv.ar(in13, 2048, 1, 1.0);
	out14 = PartConv.ar(in14, 2048, 1, 1.0);
	out15 = PartConv.ar(in15, 2048, 1, 1.0);
	out16 = PartConv.ar(in16, 2048, 1, 1.0);

	Out.ar(0, [out1, out2, out3, out4, out5, out6, out7, out8, out9, out10, out11, out12, out13, out14, out15, out16]);
}).store;


// reverb buffer hardcoded to 1 !!
SynthDef(\grain_16ch, {

	|
	bufnum=0, lvl=0.5, rate=1.0, start=0.0,

	//lowpass
	lp_freq=19000, lp_q=0.1, lp_dist=0.0, lp_freq_lfo_freq=0.0, lp_freq_lfo_depth = 0.0, lp_freq_lfo_phase = 0.0,

	// peak
	pf_freq=4000, pf_q=0.1, pf_gain=0.0,

	// hi-pass
	hp_freq=20, hp_q=0.3,

	// env
	a=0.01, length=1, r=0.02, pos=0.0, rev=0.0
	|

	var lim_gain = min(lvl, 1.0);
	var cutenv = Env.new([0, lim_gain, lim_gain, 0], [a, length, r]);
	var outenv = Env.new([0, lim_gain, lim_gain, 0], [a, length + 1.5, r]);
	var sample = PlayBuf.ar(1, bufnum, rate, 1, startPos: BufDur.ir(bufnum) * 44100 * start, loop: 1) * EnvGen.ar(cutenv);
	var sample_hp = BHiPass.ar(sample, hp_freq, hp_q);
	var sample_peak = BPeakEQ.ar(sample_hp, pf_freq, pf_q, pf_gain);
	var sample_lp = LPF18.ar(sample_peak, lp_freq - ((lp_freq * lp_freq_lfo_depth) * SinOsc.ar(lp_freq_lfo_freq, lp_freq_lfo_phase)), lp_q, lp_dist);
	var out =  PanAz.ar(16, sample_lp * EnvGen.ar(cutenv, doneAction:2), pos * 0.125, orientation: 0);
	Out.ar(0, out * (1.0 - rev));
	Out.ar(16, out * rev);
}).store;

0.exit;