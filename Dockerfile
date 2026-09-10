FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV DISPLAY=:99

RUN apt-get update && apt-get install -y \
    xvfb x11vnc novnc websockify \
    curl wget unzip sudo \
    openjdk-17-jdk-headless \
    libgl1-mesa-dri libpulse0 libnss3 libatk-bridge2.0-0 \
    libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 \
    libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libasound2 \
    && rm -rf /var/lib/apt/lists/*

# Android SDK
RUN mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools && \
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip \
         -O /tmp/cmdline-tools.zip && \
    unzip -q -o /tmp/cmdline-tools.zip -d /tmp/cmdline-tools && \
    mv /tmp/cmdline-tools/cmdline-tools ${ANDROID_SDK_ROOT}/cmdline-tools/latest && \
    rm -rf /tmp/cmdline-tools /tmp/cmdline-tools.zip

# SDK components
RUN yes | ${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager --licenses >/dev/null 2>&1 && \
    ${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager \
        "platform-tools" \
        "emulator" \
        "platforms;android-34" \
        "system-images;android-34;default;x86_64" 2>&1 | tail -5

# KVM group
RUN groupadd -r kvm 2>/dev/null; useradd -m -G kvm runner

COPY --chown=runner:runner launch.sh /home/runner/launch.sh
RUN chmod +x /home/runner/launch.sh

USER runner
WORKDIR /home/runner

EXPOSE 6080 5900 5555

CMD ["./launch.sh"]
