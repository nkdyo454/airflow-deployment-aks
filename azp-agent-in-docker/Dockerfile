FROM ubuntu:22.04

RUN apt update && apt upgrade -y && \
    apt install -y ca-certificates curl apt-transport-https lsb-release gnupg jq libicu-dev git && \
    curl -sL https://aka.ms/InstallAzureCLIDeb | bash && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -m agent

# Also can be "linux-arm", "linux-arm64".
ENV TARGETARCH="linux-x64"

WORKDIR /azp
COPY ./start.sh /azp/
RUN chmod +x /azp/start.sh && \
    chown -R agent:agent /azp && \
    chmod 755 /azp
USER agent

ENTRYPOINT [ "./start.sh" ]
