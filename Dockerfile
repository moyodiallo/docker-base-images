FROM ocaml/opam:debian-12-ocaml-4.14@sha256:45b04e2a4c933c57549382045dfac12cb7e872cace0456f92f4b022066e48111 as build
RUN sudo apt-get update && sudo apt-get install libev-dev capnproto graphviz m4 pkg-config libsqlite3-dev libgmp-dev libssl-dev libffi-dev -y --no-install-recommends
RUN cd ~/opam-repository && git fetch -q origin master && git reset --hard cf93548ddc4f36b87b006f4858fac7ae73ccaa0f && opam update
COPY --chown=opam \
	ocurrent/current.opam \
	ocurrent/current_web.opam \
	ocurrent/current_docker.opam \
	ocurrent/current_git.opam \
	ocurrent/current_github.opam \
	ocurrent/current_slack.opam \
	ocurrent/current_rpc.opam \
	/src/ocurrent/
COPY --chown=opam \
        ocluster/*.opam \
        /src/ocluster/
WORKDIR /src
RUN opam pin add -yn current_docker.dev "./ocurrent" && \
    opam pin add -yn current_git.dev "./ocurrent" && \
    opam pin add -yn current_github.dev "./ocurrent" && \
    opam pin add -yn current.dev "./ocurrent" && \
    opam pin add -yn current_rpc.dev "./ocurrent" && \
    opam pin add -yn current_slack.dev "./ocurrent" && \
    opam pin add -yn current_web.dev "./ocurrent" && \
    opam pin add -yn current_ocluster.dev "./ocluster" && \
    opam pin add -yn ocluster-api.dev "./ocluster"
COPY --chown=opam base-images.opam /src/
RUN opam install -y --deps-only .
ADD --chown=opam . .
RUN opam config exec -- dune build ./src/base_images.exe

FROM debian:12
RUN apt-get update && apt-get install libev4 curl git graphviz libsqlite3-dev ca-certificates netbase gnupg2 -y --no-install-recommends
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
RUN echo 'deb https://download.docker.com/linux/debian bookworm stable' >> /etc/apt/sources.list
RUN apt-get update && apt-get install docker-ce docker-buildx-plugin -y --no-install-recommends
COPY --from=build /src/_build/default/src/base_images.exe /usr/local/bin/base-images
WORKDIR /var/lib/ocurrent
ENTRYPOINT ["/usr/local/bin/base-images"]
