/// «1 clase», «2 clases». Para frases con otra palabra, pasa [many] (p. ej. «1 salón», «2 salones»).
String plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';
