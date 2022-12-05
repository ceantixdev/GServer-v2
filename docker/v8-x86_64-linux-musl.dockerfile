FROM alpine:3.12 as gn-builder
ARG GN_COMMIT=82d673acb802cee21534c796a59f8cdf26500f53
RUN apk add --update --virtual .gn-build-dependencies \
		alpine-sdk \
		binutils-gold \
		clang \
		curl \
		git \
		llvm9 \
		ninja \
		python3 \
		tar \
		xz \
	&& PATH=$PATH:/usr/lib/llvm4/bin \
	&& cp -f /usr/bin/ld.gold /usr/bin/ld \
	&& git clone https://gn.googlesource.com/gn /tmp/gn \
	&& git -C /tmp/gn checkout ${GN_COMMIT} \
	&& cd /tmp/gn \
	&& python3 build/gen.py \
	&& ninja -C out \
	&& cp -f /tmp/gn/out/gn /usr/local/bin/gn \
	&& apk del .gn-build-dependencies \
	&& rm -rf /tmp/* /var/tmp/* /var/cache/apk/*

# Google V8 Clone Environment
# gclient does NOT work with Alpine
FROM debian:buster-slim as source
ARG V8_VERSION=9.1.269.9
RUN set -x && \
	apt-get update && \
	apt-get install -y \
		git \
		curl \
		python3 && \
	git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git /tmp/depot_tools && \
	PATH=$PATH:/tmp/depot_tools && \
	cd /tmp && \
	fetch v8 && \
	cd /tmp/v8 && \
	git checkout ${V8_VERSION} && \
	gclient sync -D && \
	apt-get remove --purge -y \
		git \
		curl \
		python3 && \
	apt-get autoremove -y && \
	rm -rf /var/lib/apt/lists/*

# Google V8 Build Environment
FROM alpine:3.12 as v8
COPY --from=source /tmp/v8 /tmp/v8
COPY --from=gn-builder /usr/local/bin/gn /tmp/v8/buildtools/linux64/gn
RUN \
	apk add --update --virtual .v8-build-dependencies \
		curl \
		g++ \
		gcc \
		glib-dev \
		icu-dev \
		libstdc++ \
		linux-headers \
		make \
		ninja \
		python2 \
		tar \
		xz \
	&& cd /tmp/v8 && \
	python2 ./tools/dev/v8gen.py x64.release -- \
		is_component_build=false \
		is_debug=false \
		use_custom_libcxx=false \
		v8_monolithic=true \
		v8_use_external_startup_data=false \
		binutils_path=\"/usr/bin\" \
		target_os=\"linux\" \
		target_cpu=\"x64\" \
		v8_target_cpu=\"x64\" \
		v8_enable_future=true \
		is_official_build=false \
		is_cfi=false \
		is_clang=false \
		use_custom_libcxx=false \
		use_sysroot=false \
		use_gold=false \
		treat_warnings_as_errors=false \
		symbol_level=0 \
		strip_debug_info=true \
		v8_use_external_startup_data=false \
		v8_enable_i18n_support=false \
		v8_enable_gdbjit=false \
		v8_static_library=true \
		v8_enable_pointer_compression=false \
	&& ninja -C out.gn/x64.release -j $(getconf _NPROCESSORS_ONLN) \
	&& find /tmp/v8/out.gn/x64.release -name '*.a' \
	&& rm -rf /tmp/v8/third_party /tmp/v8/test \
	&& apk del --purge .v8-build-dependencies

FROM alpine:3.12 as v8-final
COPY --from=v8 /tmp/v8 /tmp/v8
